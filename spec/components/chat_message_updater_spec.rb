# frozen_string_literal: true

require 'rails_helper'

describe DiscourseChat::ChatMessageUpdater do
  fab!(:admin1) { Fabricate(:admin) }
  fab!(:admin2) { Fabricate(:admin) }
  fab!(:user1) { Fabricate(:user) }
  fab!(:user2) { Fabricate(:user) }
  fab!(:user3) { Fabricate(:user) }
  fab!(:user4) { Fabricate(:user) }
  fab!(:user_without_memberships) { Fabricate(:user) }
  fab!(:public_chat_channel) { Fabricate(:chat_channel, chatable: Fabricate(:topic)) }

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    Jobs.run_immediately!

    [admin1, admin2, user1, user2, user3, user4].each do |user|
      Fabricate(:user_chat_channel_membership, chat_channel: public_chat_channel, user: user)
    end
    @direct_message_channel = DiscourseChat::DirectMessageChannelCreator.create!([user1, user2])
  end

  def create_chat_message(user, message, channel, upload_ids: nil)
    creator = DiscourseChat::ChatMessageCreator.create(
      chat_channel: channel,
      user: user,
      in_reply_to_id: nil,
      content: message,
      upload_ids: upload_ids
    )
    creator.chat_message
  end

  it "it updates a messages content" do
    chat_message = create_chat_message(user1, "This will be changed", public_chat_channel)
    new_message = "Change to this!"

    DiscourseChat::ChatMessageUpdater.update(
      chat_message: chat_message,
      new_content: new_message
    )
    expect(chat_message.reload.message).to eq(new_message)
  end

  it "creates mention notifications for unmentioned users" do
    chat_message = create_chat_message(user1, "This will be changed", public_chat_channel)
    expect {
      DiscourseChat::ChatMessageUpdater.update(
        chat_message: chat_message,
        new_content: "this is a message with @system @mentions @#{user2.username} and @#{user3.username}"
      )
    }.to change { user2.chat_mentions.count }.by(1)
      .and change {
        user3.chat_mentions.count
      }.by(1)
  end

  it "doesn't create mentions for already mentioned users" do
    message = "ping @#{user2.username} @#{user3.username}"
    chat_message = create_chat_message(user1, message, public_chat_channel)
    expect {
      DiscourseChat::ChatMessageUpdater.update(
        chat_message: chat_message,
        new_content: message + " editedddd"
      )
    }.to change { ChatMention.count }.by(0)
  end

  it "doesn't create mentions for users without access" do
    message = "ping"
    chat_message = create_chat_message(user1, message, public_chat_channel)

    expect {
      DiscourseChat::ChatMessageUpdater.update(
        chat_message: chat_message,
        new_content: message + " @#{user_without_memberships.username}"
      )
    }.to change { ChatMention.count }.by(0)
  end

  it "destroys mention notifications that should be removed" do
    chat_message = create_chat_message(user1, "ping @#{user2.username} @#{user3.username}", public_chat_channel)
    expect {
      DiscourseChat::ChatMessageUpdater.update(
        chat_message: chat_message,
        new_content: "ping @#{user3.username}"
      )
    }.to change { user2.chat_mentions.count }.by(-1)
      .and change {
        user3.chat_mentions.count
      }.by(0)
  end

  it "creates new, leaves existing, and removes old mentions all at once" do
    chat_message = create_chat_message(user1, "ping @#{user2.username} @#{user3.username}", public_chat_channel)
    DiscourseChat::ChatMessageUpdater.update(
      chat_message: chat_message,
      new_content: "ping @#{user3.username} @#{user4.username}"
    )

    expect(user2.chat_mentions.where(chat_message: chat_message)).not_to be_present
    expect(user3.chat_mentions.where(chat_message: chat_message)).to be_present
    expect(user4.chat_mentions.where(chat_message: chat_message)).to be_present
  end

  it "does not create new mentions in direct message for users who don't have access" do
    chat_message = create_chat_message(user1, "ping nobody" , @direct_message_channel)
    expect {
      DiscourseChat::ChatMessageUpdater.update(
        chat_message: chat_message,
        new_content: "ping @#{admin1.username}"
      )
    }.to change { ChatMention.count }.by(0)
  end

  it "creates a chat_message_revision record" do
    old_message = "It's a thrsday!"
    new_message = "It's a thursday!"
    chat_message = create_chat_message(user1, old_message, public_chat_channel)
    DiscourseChat::ChatMessageUpdater.update(
      chat_message: chat_message,
      new_content: new_message
    )
    revision = chat_message.revisions.last
    expect(revision.old_message).to eq(old_message)
    expect(revision.new_message).to eq(new_message)
  end

  describe "uploads" do
    fab!(:upload1) { Fabricate(:upload, user: user1) }
    fab!(:upload2) { Fabricate(:upload, user: user1) }

    it "does nothing if the passed in upload_ids match the existing upload_ids" do
      chat_message = create_chat_message(user1, "something", public_chat_channel, upload_ids: [upload1.id, upload2.id])
      expect {
        DiscourseChat::ChatMessageUpdater.update(
          chat_message: chat_message,
          new_content: "I guess this is different",
          upload_ids: [upload2.id, upload1.id]
        )
      }.to change { ChatUpload.count }.by(0)
    end

    it "removes uploads that should be removed" do
      chat_message = create_chat_message(user1, "something", public_chat_channel, upload_ids: [upload1.id, upload2.id])
      expect {
        DiscourseChat::ChatMessageUpdater.update(
          chat_message: chat_message,
          new_content: "I guess this is different",
          upload_ids: [upload1.id]
        )
      }.to change { ChatUpload.where(upload_id: upload2.id).count }.by(-1)
    end

    it "removes all uploads if they should be removed" do
      chat_message = create_chat_message(user1, "something", public_chat_channel, upload_ids: [upload1.id, upload2.id])
      expect {
        DiscourseChat::ChatMessageUpdater.update(
          chat_message: chat_message,
          new_content: "I guess this is different",
          upload_ids: []
        )
      }.to change { ChatUpload.where(chat_message: chat_message).count }.by(-2)
    end

    it "adds one upload if none exist" do
      chat_message = create_chat_message(user1, "something", public_chat_channel)
      expect {
        DiscourseChat::ChatMessageUpdater.update(
          chat_message: chat_message,
          new_content: "I guess this is different",
          upload_ids: [upload1.id]
        )
      }.to change { ChatUpload.where(chat_message: chat_message).count }.by(1)
    end

    it "adds multiple uploads if none exist" do
      chat_message = create_chat_message(user1, "something", public_chat_channel)
      expect {
        DiscourseChat::ChatMessageUpdater.update(
          chat_message: chat_message,
          new_content: "I guess this is different",
          upload_ids: [upload1.id, upload2.id]
        )
      }.to change { ChatUpload.where(chat_message: chat_message).count }.by(2)
    end

    it "doesn't remove existing uploads when BS upload ids are passed in" do
      chat_message = create_chat_message(user1, "something", public_chat_channel, upload_ids: [upload1.id])
      expect {
        DiscourseChat::ChatMessageUpdater.update(
          chat_message: chat_message,
          new_content: "I guess this is different",
          upload_ids: [0]
        )
      }.to change { ChatUpload.where(chat_message: chat_message).count }.by(0)
    end
  end
end

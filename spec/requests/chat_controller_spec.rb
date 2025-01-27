# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DiscourseChat::ChatController do
  fab!(:user) { Fabricate(:user) }
  fab!(:admin) { Fabricate(:admin) }
  fab!(:category) { Fabricate(:category) }
  fab!(:topic) { Fabricate(:topic, category: category) }
  fab!(:tag) { Fabricate(:tag) }

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
  end

  describe "#messages" do
    fab!(:chat_channel) { Fabricate(:chat_channel, chatable: topic) }
    let(:page_size) { 30 }
    let(:message_count) { 35 }

    before do
      message_count.times do |n|
        ChatMessage.create(
          chat_channel: chat_channel,
          user: user,
          message: "message #{n}",
        )
      end
      sign_in(user)
    end

    it "errors for user when they are not allowed to chat" do
      SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:staff]
      get "/chat/#{chat_channel.id}/messages.json", params: { page_size: page_size }
      expect(response.status).to eq(403)
    end

    it "errors when page size is over 50" do
      get "/chat/#{chat_channel.id}/messages.json", params: { page_size: 51 }
      expect(response.status).to eq(400)
    end

    it "errors when page size is nil" do
      get "/chat/#{chat_channel.id}/messages.json"
      expect(response.status).to eq(400)
    end

    it "returns the latest messages" do
      get "/chat/#{chat_channel.id}/messages.json", params: { page_size: page_size }
      messages = response.parsed_body["chat_messages"]
      expect(messages.count).to eq(page_size)
      expect(messages.first["id"]).to be < messages.last["id"]
    end

    it "returns messages before `before_message_id` if present" do
      before_message_id = ChatMessage
        .order(created_at: :desc)
        .to_a[page_size - 1]
        .id

      get "/chat/#{chat_channel.id}/messages.json", params: { before_message_id: before_message_id, page_size: page_size }
      messages = response.parsed_body["chat_messages"]
      expect(messages.count).to eq(message_count - page_size)
    end
  end

  describe "#enable_chat" do
    describe "for topic" do
      it "errors for non-staff" do
        sign_in(user)
        Fabricate(:chat_channel, chatable: topic)
        post "/chat/enable.json", params: { chatable_type: "topic", chatable_id: topic.id }
        expect(response.status).to eq(403)

        expect(topic.reload.custom_fields[DiscourseChat::HAS_CHAT_ENABLED]).to eq(nil)
      end

      it "Returns a 422 when chat is already enabled" do
        sign_in(admin)
        Fabricate(:chat_channel, chatable: topic)
        post "/chat/enable.json", params: { chatable_type: "topic", chatable_id: topic.id }
        expect(response.status).to eq(422)

        expect(topic.reload.custom_fields[DiscourseChat::HAS_CHAT_ENABLED]).to eq(nil)
      end

      it "Enables chat and follows the channel" do
        sign_in(admin)
        expect {
          post "/chat/enable.json", params: { chatable_type: "topic", chatable_id: topic.id }
        }.to change {
          admin.user_chat_channel_memberships.count
        }.by(1)
        expect(response.status).to eq(200)
        expect(topic.chat_channel).to be_present
        expect(topic.reload.custom_fields[DiscourseChat::HAS_CHAT_ENABLED]).to eq(true)
      end
    end

    describe "for tag" do
      it "enables chat" do
        sign_in(admin)
        post "/chat/enable.json", params: { chatable_type: "tag", chatable_id: tag.id }
        expect(response.status).to eq(200)
        expect(ChatChannel.where(chatable: tag)).to be_present
      end
    end
  end

  describe "#disable_chat" do
    describe "for topic" do
      it "errors for non-staff" do
        sign_in(user)
        Fabricate(:chat_channel, chatable: topic)

        post "/chat/disable.json", params: { chatable_type: "topic", chatable_id: topic.id }
        expect(response.status).to eq(403)
      end

      it "Returns a 200 and does nothing when chat is already disabled" do
        sign_in(admin)
        chat_channel = Fabricate(:chat_channel, chatable: topic)
        chat_channel.update(deleted_at: Time.now, deleted_by_id: admin.id)

        post "/chat/disable.json", params: { chatable_type: "topic", chatable_id: topic.id }
        expect(response.status).to eq(200)
        expect(chat_channel.reload.deleted_at).not_to be_nil
      end

      it "disables chat" do
        sign_in(admin)
        chat_channel = Fabricate(:chat_channel, chatable: topic)

        topic.custom_fields[DiscourseChat::HAS_CHAT_ENABLED] = true
        topic.save!

        post "/chat/disable.json", params: { chatable_type: "topic", chatable_id: topic.id }
        expect(response.status).to eq(200)
        expect(chat_channel.reload.deleted_by_id).to eq(admin.id)
        expect(topic.reload.custom_fields[DiscourseChat::HAS_CHAT_ENABLED]).to eq(nil)
      end
    end

    describe "for tag" do
      it "disables chat" do
        sign_in(admin)
        chat_channel = Fabricate(:chat_channel, chatable: tag)
        post "/chat/disable.json", params: { chatable_type: "tag", chatable_id: tag.id }
        expect(response.status).to eq(200)
        expect(chat_channel.reload.deleted_by_id).to eq(admin.id)
      end
    end
  end

  describe "#create_message" do
    let(:message) { "This is a message" }

    describe "for topic" do
      fab!(:chat_channel) { Fabricate(:chat_channel, chatable: topic) }

      it "errors for regular user when chat is staff-only" do
        sign_in(user)
        SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:staff]

        post "/chat/#{chat_channel.id}.json", params: { message: message }
        expect(response.status).to eq(403)
      end

      it "errors when the user isn't following the channel" do
        sign_in(user)

        post "/chat/#{chat_channel.id}.json", params: { message: message }
        expect(response.status).to eq(403)
      end

      it "sends a message for regular user when staff-only is disabled and they are following channel" do
        sign_in(user)
        UserChatChannelMembership.create(user: user, chat_channel: chat_channel, following: true)

        expect {
          post "/chat/#{chat_channel.id}.json", params: { message: message }
        }.to change { ChatMessage.count }.by(1)
        expect(response.status).to eq(200)
        expect(ChatMessage.last.message).to eq(message)
      end
    end

    describe 'for direct message' do
      fab!(:user1) { Fabricate(:user) }
      fab!(:user2) { Fabricate(:user) }
      fab!(:chatable) { Fabricate(:direct_message_channel, users: [user1, user2]) }
      fab!(:direct_message_channel) { Fabricate(:chat_channel, chatable: chatable) }

      it 'forces users to follow the channel' do
        UserChatChannelMembership.create!(user: user1, chat_channel: direct_message_channel, following: true, desktop_notification_level: UserChatChannelMembership::NOTIFICATION_LEVELS[:always], mobile_notification_level: UserChatChannelMembership::NOTIFICATION_LEVELS[:always])
        UserChatChannelMembership.create!(user: user2, chat_channel: direct_message_channel, following: false, desktop_notification_level: UserChatChannelMembership::NOTIFICATION_LEVELS[:always], mobile_notification_level: UserChatChannelMembership::NOTIFICATION_LEVELS[:always])

        expect(UserChatChannelMembership.find_by(user_id: user2.id).following).to eq(false)

        ChatPublisher.expects(:publish_new_direct_message_channel).once

        sign_in(user1)
        post "/chat/#{direct_message_channel.id}.json", params: { message: message }

        expect(UserChatChannelMembership.find_by(user_id: user2.id).following).to eq(true)
      end
    end
  end

  describe "#edit_message" do
    fab!(:chat_channel) { Fabricate(:chat_channel) }
    fab!(:chat_message) { Fabricate(:chat_message, chat_channel: chat_channel, user: user) }

    it "errors when a user tries to edit another user's message" do
      sign_in(Fabricate(:user))

      put "/chat/#{chat_channel.id}/edit/#{chat_message.id}.json", params: { new_message: "edit!" }
      expect(response.status).to eq(403)
    end

    it "errors when staff tries to edit another user's message" do
      sign_in(admin)
      new_message = "Vrroooom cars go fast"

      put "/chat/#{chat_channel.id}/edit/#{chat_message.id}.json", params: { new_message: new_message }
      expect(response.status).to eq(403)
    end

    it "allows a user to edit their own messages" do
      sign_in(user)
      new_message = "Wow markvanlan must be a good programmer"

      put "/chat/#{chat_channel.id}/edit/#{chat_message.id}.json", params: { new_message: new_message }
      expect(response.status).to eq(200)
      expect(chat_message.reload.message).to eq(new_message)
    end
  end

  RSpec.shared_examples "chat_message_deletion" do
    it "doesn't allow a user to delete another user's message" do
      sign_in(other_user)

      delete "/chat/#{chat_channel.id}/#{ChatMessage.last.id}.json"
      expect(response.status).to eq(403)
    end

    it "Allows admin to delete others' messages" do
      sign_in(admin)

      expect {
        delete "/chat/#{chat_channel.id}/#{ChatMessage.last.id}.json"
      }.to change { ChatMessage.count }.by(-1)
      expect(response.status).to eq(200)
    end
  end

  describe "#delete" do
    fab!(:second_user) { Fabricate(:user) }

    before do
      ChatMessage.create(user: user, message: "this is a message", chat_channel: chat_channel)
    end

    describe "for topic" do
      fab!(:chat_channel) { Fabricate(:chat_channel, chatable: topic) }

      it_behaves_like "chat_message_deletion" do
        let(:other_user) { second_user }
      end

      it "Allows users to delete their own messages" do
        sign_in(user)
        expect {
          delete "/chat/#{chat_channel.id}/#{ChatMessage.last.id}.json"
        }.to change { ChatMessage.count }.by(-1)
        expect(response.status).to eq(200)
      end
    end

    describe "for category" do
      fab!(:chat_channel) { Fabricate(:chat_channel, chatable: category) }

      it_behaves_like "chat_message_deletion" do
        let(:other_user) { second_user }
      end

      it "Allows users to delete their own messages" do
        sign_in(user)
        expect {
          delete "/chat/#{chat_channel.id}/#{ChatMessage.last.id}.json"
        }.to change { ChatMessage.count }.by(-1)
        expect(response.status).to eq(200)
      end
    end
  end

  RSpec.shared_examples "chat_message_restoration" do
    it "doesn't allow a user to restore another user's message" do
      sign_in(other_user)

      put "/chat/#{chat_channel.id}/restore/#{ChatMessage.unscoped.last.id}.json"
      expect(response.status).to eq(403)
    end

    it "allows a user to restore their own posts" do
      sign_in(user)

      deleted_message = ChatMessage.unscoped.last
      put "/chat/#{chat_channel.id}/restore/#{deleted_message.id}.json"
      expect(response.status).to eq(200)
      expect(deleted_message.reload.deleted_at).to eq(nil)
    end

    it "allows admin to restore others' posts" do
      sign_in(admin)

      deleted_message = ChatMessage.unscoped.last
      put "/chat/#{chat_channel.id}/restore/#{deleted_message.id}.json"
      expect(response.status).to eq(200)
      expect(deleted_message.reload.deleted_at).to eq(nil)
    end
  end

  describe "#restore" do
    fab!(:second_user) { Fabricate(:user) }

    before do
      message = ChatMessage.create(user: user, message: "this is a message", chat_channel: chat_channel)
      message.update(deleted_at: Time.now, deleted_by_id: user.id)
    end

    describe "for topic" do
      fab!(:chat_channel) { Fabricate(:chat_channel, chatable: topic) }

      it_behaves_like "chat_message_restoration" do
        let(:other_user) { second_user }
      end

      it "doesn't allow restoration of posts on closed topics" do
        sign_in(user)
        topic.update(closed: true)

        put "/chat/#{chat_channel.id}/restore/#{ChatMessage.unscoped.last.id}.json"
        expect(response.status).to eq(403)
      end

      it "doesn't allow restoration of posts on archived topics" do
        sign_in(user)
        topic.update(archived: true)

        put "/chat/#{chat_channel.id}/restore/#{ChatMessage.unscoped.last.id}.json"
        expect(response.status).to eq(403)
      end
    end

    describe "for category" do
      fab!(:chat_channel) { Fabricate(:chat_channel, chatable: category) }

      it_behaves_like "chat_message_restoration" do
        let(:other_user) { second_user }
      end
    end
  end

  describe "#update_user_last_read" do
    fab!(:chat_channel) { Fabricate(:chat_channel, chatable: topic) }
    fab!(:chat_message) { Fabricate(:chat_message, chat_channel: chat_channel, user: user) }

    before { sign_in(user) }

    it "updates timing records" do
      existing_record = UserChatChannelMembership.create(
        chat_channel: chat_channel,
        last_read_message_id: 0,
        user: user
      )

      expect {
        put "/chat/#{chat_channel.id}/read/#{chat_message.id}.json"
      }.to change { UserChatChannelMembership.count }.by(0)
      existing_record.reload
      expect(existing_record.chat_channel_id).to eq(chat_channel.id)
      expect(existing_record.last_read_message_id).to eq(chat_message.id)
      expect(existing_record.user_id).to eq(user.id)
    end

    it "marks mention notifications as read" do
      existing_record = UserChatChannelMembership.create(
        chat_channel: chat_channel,
        last_read_message_id: 0,
        user: user
      )
      notification = Notification.create!(
        notification_type: Notification.types[:chat_mention],
        user: user,
        high_priority: true,
        data: {
          message: 'chat.mention_notification',
          chat_message_id: chat_message.id,
          chat_channel_id: chat_channel.id,
          chat_channel_title: chat_channel.title(user),
          mentioned_by_username: user.username,
        }.to_json
      )
      ChatMention.create(
        user: user,
        chat_message: chat_message,
        notification: notification
      )

      put "/chat/#{chat_channel.id}/read/#{chat_message.id}.json"
      expect(response.status).to eq(200)
      expect(notification.reload.read).to eq(true)
    end
  end

  describe "react" do
    fab!(:chat_channel) { Fabricate(:chat_channel) }
    fab!(:chat_message) { Fabricate(:chat_message, chat_channel: chat_channel, user: user) }
    fab!(:user_membership) { Fabricate(:user_chat_channel_membership, chat_channel: chat_channel, user: user) }

    fab!(:private_chat_channel) { Fabricate(:chat_channel, chatable: Fabricate(:private_category, group: Fabricate(:group))) }
    fab!(:private_chat_message) { Fabricate(:chat_message, chat_channel: private_chat_channel, user: admin) }
    fab!(:priate_user_membership) { Fabricate(:user_chat_channel_membership, chat_channel: private_chat_channel, user: user) }

    fab!(:chat_channel_no_memberships) { Fabricate(:chat_channel) }
    fab!(:chat_message_no_memberships) { Fabricate(:chat_message, chat_channel: chat_channel_no_memberships, user: user) }

    it "errors with invalid emoji" do
      sign_in(user)
      put "/chat/#{chat_channel.id}/react/#{chat_message.id}.json", params: { emoji: 12, react_action: "add" }
      expect(response.status).to eq(400)
    end

    it "errors with invalid action" do
      sign_in(user)
      put "/chat/#{chat_channel.id}/react/#{chat_message.id}.json", params: { emoji: ":heart:", react_action: "sdf" }
      expect(response.status).to eq(400)
    end

    it "errors when user tries to react to channel without a membership record" do
      sign_in(user)
      put "/chat/#{chat_channel_no_memberships.id}/react/#{chat_message_no_memberships.id}.json", params: { emoji: ":heart:", react_action: "add" }
      expect(response.status).to eq(403)
    end

    it "errors when user tries to react to private channel they can't access" do
      sign_in(user)
      put "/chat/#{private_chat_channel.id}/react/#{private_chat_message.id}.json", params: { emoji: ":heart:", react_action: "add" }
      expect(response.status).to eq(403)
    end

    it "adds a reaction record correctly" do
      sign_in(user)
      emoji = ":heart:"
      expect {
        put "/chat/#{chat_channel.id}/react/#{chat_message.id}.json", params: { emoji: emoji, react_action: "add" }
      }.to change { chat_message.reactions.where(user: user, emoji: emoji).count }.by(1)
      expect(response.status).to eq(200)
    end

    it "removes a reaction record correctly" do
      sign_in(user)
      emoji = ":heart:"
      chat_message.reactions.create(user: user, emoji: emoji)
      expect {
        put "/chat/#{chat_channel.id}/react/#{chat_message.id}.json", params: { emoji: emoji, react_action: "remove" }
      }.to change { chat_message.reactions.where(user: user, emoji: emoji).count }.by(-1)
      expect(response.status).to eq(200)
    end
  end

  describe "invite_users" do
    fab!(:chat_channel) { Fabricate(:chat_channel) }
    fab!(:chat_message) { Fabricate(:chat_message, chat_channel: chat_channel, user: admin) }
    fab!(:user2) { Fabricate(:user) }

    before do
      sign_in(admin)

      [user, user2].each do |u|
        u.user_option.update(chat_enabled: true)
      end
    end

    it "doesn't invite users who cannot chat" do
      SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:admin]
      expect {
        put "/chat/#{chat_channel.id}/invite.json", params: { user_ids: [user.id] }
      }.to change { user.notifications.where(notification_type: Notification.types[:chat_invitation]).count }.by(0)
    end

    it "creates an invitation notification for users who can chat" do
      expect {
        put "/chat/#{chat_channel.id}/invite.json", params: { user_ids: [user.id] }
      }.to change { user.notifications.where(notification_type: Notification.types[:chat_invitation]).count }.by(1)
    end

    it "creates multiple invitations" do
      expect {
        put "/chat/#{chat_channel.id}/invite.json", params: { user_ids: [user.id, user2.id] }
      }.to change {
        Notification.where(notification_type: Notification.types[:chat_invitation], user_id: [user.id, user2.id]).count
      }.by(2)
    end

    it "adds chat_message_id when param is present" do
      put "/chat/#{chat_channel.id}/invite.json", params: { user_ids: [user.id], chat_message_id: chat_message.id }
      expect(JSON.parse(Notification.last.data)["chat_message_id"]).to eq(chat_message.id.to_s)
    end
  end
end

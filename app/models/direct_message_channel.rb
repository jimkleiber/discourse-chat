# frozen_string_literal: true

class DirectMessageChannel < ActiveRecord::Base
  has_many :direct_message_users
  has_many :users, through: :direct_message_users

  def user_can_access?(user)
    users.include?(user)
  end

  def chat_channel_title_for_user(chat_channel, user)
    return chat_channel.id if users.size > 2

    users = direct_message_users.map(&:user) - [user]

    return "@#{user.username}" if users.empty?
    return chat_channel.id if !users.first

    "@#{users.first.username}"
  end

  def self.for_user_ids(user_ids)
    joins(:users)
      .group("direct_message_channels.id")
      .having("ARRAY[?] = ARRAY_AGG(users.id ORDER BY users.id)", user_ids.sort)
      &.first
  end
end

# == Schema Information
#
# Table name: direct_message_channels
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

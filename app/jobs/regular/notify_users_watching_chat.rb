# frozen_string_literal: true

module Jobs
  class NotifyUsersWatchingChat < ::Jobs::Base
    def execute(args = {})
      @chat_message = ChatMessage.includes(:user, chat_channel: :chatable).find_by(id: args[:chat_message_id])
      return if @chat_message.nil?

      @creator = @chat_message.user
      @chat_channel = @chat_message.chat_channel

      always_notification_level = UserChatChannelMembership::NOTIFICATION_LEVELS[:always]

      UserChatChannelMembership
        .includes(user: :groups)
        .joins(user: :user_option)
        .where(user_option: { chat_enabled: true })
        .where.not(user_id: args[:except_user_ids])
        .where(chat_channel_id: @chat_channel.id)
        .where(following: true)
        .where("desktop_notification_level = ? OR mobile_notification_level = ?",
               always_notification_level, always_notification_level)
        .merge(User.not_suspended)
        .each do |membership|
        send_notifications(membership)
      end
    end

    def send_notifications(membership)
      user = membership.user
      guardian = Guardian.new(user)
      return unless guardian.can_chat?(user) && guardian.can_see_chat_channel?(@chat_channel)
      return if DiscourseChat::ChatNotifier.user_has_seen_message?(membership, @chat_message.id)
      return if online_user_ids.include?(user.id)

      translated_title = @chat_channel.group_direct_message_channel? ?
        I18n.t("discourse_push_notifications.popup.group_chat_message") :
        I18n.t("discourse_push_notifications.popup.chat_message",
               chat_channel_title: @chat_channel.title(user)
              )

      payload = {
        username: @creator.username,
        notification_type: Notification.types[:chat_message],
        post_url: "/chat/channel/#{@chat_channel.id}/#{@chat_channel.title(user)}",
        translated_title: translated_title,
        tag: DiscourseChat::ChatNotifier.push_notification_tag(:message, @chat_channel.id),
        excerpt: @chat_message.push_notification_excerpt
      }
      if membership.desktop_notifications_always?
        MessageBus.publish("/chat/notification-alert/#{user.id}", payload, user_ids: [user.id])
      end

      if membership.mobile_notifications_always? && !online_user_ids.include?(user.id)
        PostAlerter.push_notification(user, payload)
      end
    end

    def online_user_ids
      @online_user_ids ||= PresenceChannel.new("/chat/online").user_ids
    end
  end
end

# frozen_string_literal: true

class DiscourseChat::ChatChannelsController < DiscourseChat::ChatBaseController
  def index
    structured = DiscourseChat::ChatChannelFetcher.structured(guardian)
    render_serialized(structured, ChatChannelIndexSerializer, root: false)
  end

  def all
    channels = DiscourseChat::ChatChannelFetcher.structured_public_channels(
      guardian,
      UserChatChannelMembership.where(user: current_user),
      scope_with_membership: false
    )

    render_serialized(channels, ChatChannelSettingsSerializer)
  end

  def show
    set_channel_and_chatable
    render_serialized(@chat_channel, ChatChannelSerializer)
  end

  def follow
    params.require(:chat_channel_id)

    membership = UserChatChannelMembership.includes(:chat_channel).find_or_create_by(
      user_id: current_user.id,
      chat_channel_id: params[:chat_channel_id]
    )
    membership.following = true
    if (membership.save)
      render_serialized(membership, UserChatChannelMembershipSerializer, root: false)
    else
      render_json_error(membership)
    end
  end

  def unfollow
    params.require(:chat_channel_id)

    membership = UserChatChannelMembership
      .includes(:chat_channel)
      .find_by(
        user_id: current_user.id,
        chat_channel_id: params[:chat_channel_id]
      )
    if (membership && membership.update(following: false))
      render json: success_json
    else
      render_json_error(membership)
    end
  end

  def notification_settings
    params.require([
      :chat_channel_id,
      :muted,
      :desktop_notification_level,
      :mobile_notification_level
    ])

    membership = UserChatChannelMembership.find_by(
      user_id: current_user.id,
      chat_channel_id: params[:chat_channel_id]
    )
    raise Discourse::NotFound unless membership

    if membership.update(
      muted: params[:muted],
      desktop_notification_level: params[:desktop_notification_level],
      mobile_notification_level: params[:mobile_notification_level]
    )
      render json: success_json
    else
      render_json_error(membership)
    end
  end
end
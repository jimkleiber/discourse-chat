# frozen_string_literal: true

require_dependency "application_controller"

class DiscourseTopicChat::ChatController < ::ApplicationController
  requires_plugin DiscourseTopicChat::PLUGIN_NAME
  before_action :ensure_logged_in, only: [:send_chat]

  def enable_chat
    t = Topic.find(params[:topic_id])
    guardian.ensure_can_see!(t)
    guardian.ensure_can_enable_chat!(t)

    success = true

    tc = TopicChat.with_deleted.find_by(topic_id: t.id)
    if tc && tc.trashed?
      tc.recover!
    else if tc
      return render_json_error I18n.t("chat.already_enabled")
    end
      tc = TopicChat.new(topic_id: t.id)
    end

    success = tc.save
    if success
      t.add_small_action(current_user, 'chat.enabled', current_user)
    end

    success ? (render json: success_json) : render_json_error(tc)
  end

  def disable_chat
    t = Topic.with_deleted.find(params[:topic_id])
    guardian.ensure_can_see!(t)
    guardian.ensure_can_enable_chat!(t)

    tc = TopicChat.with_deleted.find_by(topic_id: t.id)
    if tc.trashed?
      return render_json_error I18n.t("chat.already_disabled")
    end
    tc.trash!(current_user)

    success = tc.save
    if success
      t.add_small_action(current_user, 'chat.disabled', current_user)
    end

    success ? (render json: success_json) : (render_json_error(tc))
  end

  def send_chat
    t = Topic.find(params[:topic_id])
    raise Discourse::NotFound unless guardian.can_see?(t)
    tc = TopicChat.find_by(topic: t)
    raise Discourse::NotFound unless tc
    guardian.ensure_can_chat!(tc)

    post_id = params[:post_id]
    if post_id
      raise Discourse::NotFound if Post.find(post_id).topic_id != t.id
    end

    reply_to_msg_id = params[:in_reply_to_id]
    if reply_to_msg_id
      rm = TopicChatMessage.find(reply_to_msg_id)
      raise Discourse::NotFound if rm.topic_id != t.id
      post_id = rm.post_id
    end

    # chat can't be viewed on a small-action
    post_id ||= t.posts.where(post_type: Post.types[:regular]).last.id
    content = params[:message]

    msg = TopicChatMessage.new(
      topic_id: t.id,
      post_id: post_id,
      user_id: current_user.id,
      in_reply_to_id: reply_to_msg_id,
      message: content,
    )
    if !msg.save
      return render_json_error(msg)
    end

    TopicChatPublisher.publish_new!(t, msg)
    render json: success_json
  end

  def recent
    topic = Topic.find(params[:topic_id])
    raise Discourse::NotFound unless guardian.can_see?(topic)
    tc = TopicChat.find_by(topic: topic)
    raise Discourse::NotFound unless tc

    # n.b.: must fetch ID before querying DB
    message_bus_last_id = TopicChatPublisher.last_id(topic)
    messages = TopicChatMessage.where(topic: topic).order(created_at: :desc).limit(20)

    render_serialized(TopicChatView.new(topic, messages, message_bus_last_id), TopicChatViewSerializer, root: :topic_chat_view)
  end

  def historical
    t = Topic.with_deleted.find(params[:topic_id])
    raise Discourse::NotFound unless guardian.can_see?(t)
    tc = TopicChat.with_deleted.find_by(topic: t)
    raise Discourse::NotFound unless tc

    post_id = params[:post_id]
    p = Post.find(post_id)
    raise Discourse::NotFound if p.topic_id != t.id

    raise NotImplementedError
  end

  def delete
    raise NotImplementedError
  end

  def flag
    raise NotImplementedError
  end

  def index
    # not implemented...

    render json: success_json
  end
end
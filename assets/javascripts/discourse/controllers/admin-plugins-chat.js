import Controller from "@ember/controller";
import bootbox from "bootbox";
import discourseComputed from "discourse-common/utils/decorators";
import EmberObject, { action } from "@ember/object";
import I18n from "I18n";
import { and } from "@ember/object/computed";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default Controller.extend({
  queryParams: { selectedWebhookId: "id" },

  loading: false,
  creatingNew: false,
  newWebhookName: "",
  newWebhookChannelId: null,
  nameAndChannelValid: and("newWebhookName", "newWebhookChannelId"),
  emojiPickerIsActive: false,

  @discourseComputed("model.incoming_chat_webhooks.@each.updated_at")
  sortedWebhooks(webhooks) {
    return webhooks?.sortBy("updated_at").reverse() || [];
  },

  @discourseComputed("selectedWebhookId")
  selectedWebhook(id) {
    if (!id) {
      return;
    }

    id = parseInt(id, 10);
    return this.model.incoming_chat_webhooks.findBy("id", id);
  },

  @discourseComputed("selectedWebhook.name", "selectedWebhook.chat_channel.id")
  saveEditDisabled(name, chatChannelId) {
    return !name || !chatChannelId;
  },

  @action
  createNewWebhook() {
    if (this.loading) {
      return;
    }

    this.set("loading", true);
    const data = {
      name: this.newWebhookName,
      chat_channel_id: this.newWebhookChannelId,
    };

    return ajax("/admin/plugins/chat/hooks", { data, type: "POST" })
      .then((webhook) => {
        const newWebhook = EmberObject.create(webhook);
        this.set(
          "model.incoming_chat_webhooks",
          [newWebhook].concat(this.model.incoming_chat_webhooks)
        );
        this.resetNewWebhook();
        this.setProperties({
          loading: false,
          selectedWebhookId: newWebhook.id,
        });
      })
      .catch(popupAjaxError);
  },

  @action
  resetNewWebhook() {
    this.setProperties({
      creatingNew: false,
      newWebhookName: "",
      newWebhookChannelId: null,
    });
  },

  @action
  destroyWebhook(webhook) {
    bootbox.confirm(
      I18n.t("chat.incoming_webhooks.confirm_destroy"),
      (confirm) => {
        if (!confirm) {
          return;
        }

        this.set("loading", true);
        return ajax(`/admin/plugins/chat/hooks/${webhook.id}`, {
          type: "DELETE",
        })
          .then(() => {
            this.model.incoming_chat_webhooks.removeObject(webhook);
            this.set("loading", false);
          })
          .catch(popupAjaxError);
      }
    );
  },

  @action
  emojiSelected(emoji) {
    this.selectedWebhook.set("emoji", `:${emoji}:`);
    return this.set("emojiPickerIsActive", false);
  },

  @action
  saveEdit() {
    this.set("loading", true);
    const data = {
      name: this.selectedWebhook.name,
      chat_channel_id: this.selectedWebhook.chat_channel.id,
      description: this.selectedWebhook.description,
      emoji: this.selectedWebhook.emoji,
      username: this.selectedWebhook.username,
    };
    return ajax(`/admin/plugins/chat/hooks/${this.selectedWebhook.id}`, {
      data,
      type: "PUT",
    })
      .then(() => {
        this.selectedWebhook.set("updated_at", new Date());
        this.setProperties({
          loading: false,
          selectedWebhookId: null,
        });
      })
      .catch(popupAjaxError);
  },

  @action
  changeChatChannel(chatChannelId) {
    this.selectedWebhook.set(
      "chat_channel",
      this.model.chat_channels.findBy("id", chatChannelId)
    );
  },
});

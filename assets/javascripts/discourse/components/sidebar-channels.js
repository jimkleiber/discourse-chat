import Component from "@ember/component";
import { action } from "@ember/object";
import { inject as service } from "@ember/service";

export default Component.extend({
  publicChannels: null,
  directMessageChannels: null,
  toggleSection: null,
  chat: service(),
  router: service(),

  didInsertElement() {
    this._super(...arguments);
    this.fetchChannels();
  },

  @action
  fetchChannels() {
    this.chat.getChannels().then((channels) => {
      this.setProperties({
        publicChannels: channels.publicChannels,
        directMessageChannels: channels.directMessageChannels,
      });
    });
  },

  @action
  switchChannel(channel) {
    if (
      this.site.mobileView ||
      this.router.currentRouteName === "chat.channel"
    ) {
      return this.router.transitionTo("chat.channel", channel.title);
    } else {
      this.appEvents.trigger("chat:open-channel", channel);
    }
  },
});
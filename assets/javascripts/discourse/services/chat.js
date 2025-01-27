import { popupAjaxError } from "discourse/lib/ajax-error";
import EmberObject from "@ember/object";
import KeyValueStore from "discourse/lib/key-value-store";
import Service, { inject as service } from "@ember/service";
import Site from "discourse/models/site";
import { addChatToolbarButton } from "discourse/plugins/discourse-chat/discourse/components/chat-composer";
import { ajax } from "discourse/lib/ajax";
import { A } from "@ember/array";
import { defaultHomepage } from "discourse/lib/utilities";
import { generateCookFunction } from "discourse/lib/text";
import { next } from "@ember/runloop";
import { Promise } from "rsvp";
import simpleCategoryHashMentionTransform from "discourse/plugins/discourse-chat/discourse/lib/simple-category-hash-mention-transform";

export const LIST_VIEW = "list_view";
export const CHAT_VIEW = "chat_view";

const DRAFT_STORE_NAMESPACE = "discourse_chat_drafts_";
const CHAT_ONLINE_OPTIONS = {
  userUnseenTime: 300000, // 5 minutes seconds with no interaction
  browserHiddenTime: 300000, // Or the browser has been in the background for 5 minutes
};

const PUBLIC_CHANNEL_SORT_PRIOS = {
  Category: 0,
  Tag: 1,
  Topic: 2,
};

export default Service.extend({
  allChannels: null,
  appEvents: service(),
  chatNotificationManager: service(),
  cook: null,
  directMessageChannels: null,
  hasFetchedChannels: false,
  hasUnreadMessages: false,
  idToTitleMap: null,
  lastUserTrackingMessageId: null,
  messageId: null,
  presence: service(),
  presenceChannel: null,
  publicChannels: null,
  router: service(),
  sidebarActive: false,
  unreadUrgentCount: null,
  _chatOpen: false,
  _fetchingChannels: null,
  _fullScreenChatOpen: false,
  _lastNonChatRoute: null,

  init() {
    this._super(...arguments);

    if (this.currentUser?.has_chat_enabled) {
      this.set("allChannels", []);
      this._subscribeToNewDmChannelUpdates();
      this._subscribeToUserTrackingChannel();
      this._subscribeToChannelEdits();
      this.appEvents.on("page:changed", this, "_storeLastNonChatRouteInfo");
      this.presenceChannel = this.presence.getChannel("/chat/online");
      this._draftStore = new KeyValueStore(DRAFT_STORE_NAMESPACE);
    }
  },

  willDestroy() {
    this._super(...arguments);

    if (this.currentUser?.has_chat_enabled) {
      this.set("allChannels", null);
      this._unsubscribeFromNewDmChannelUpdates();
      this._unsubscribeFromUserTrackingChannel();
      this._unsubscribeFromChannelEdits();
      this._unsubscribeFromAllChatChannels();
      this.appEvents.off("page:changed", this, "_storeLastNonChatRouteInfo");
    }
  },

  _storeLastNonChatRouteInfo(data) {
    if (
      data.currentRouteName !== "chat" &&
      data.currentRouteName !== "chat.channel"
    ) {
      this.set("_lastNonChatRoute", data.url);
    }
  },

  get lastNonChatRoute() {
    return this._lastNonChatRoute && this._lastNonChatRoute !== "/"
      ? this._lastNonChatRoute
      : `discovery.${defaultHomepage()}`;
  },

  get isChatPage() {
    return (
      this.router.currentRouteName === "chat" ||
      this.router.currentRouteName === "chat.channel"
    );
  },

  get isBrowsePage() {
    return this.router.currentRouteName === "chat.browse";
  },

  loadCookFunction(categories) {
    if (this.cook) {
      return Promise.resolve(this.cook);
    }

    const prettyTextFeatures = {
      features: Site.currentProp("chat_pretty_text_features"),
    };
    return generateCookFunction(prettyTextFeatures).then((cookFunction) => {
      return this.set("cook", (raw) => {
        return simpleCategoryHashMentionTransform(
          cookFunction(raw),
          categories
        );
      });
    });
  },

  get fullScreenChatOpen() {
    return this._fullScreenChatOpen;
  },

  set fullScreenChatOpen(status) {
    this.set("_fullScreenChatOpen", status);
    this._updatePresence();
  },

  get chatOpen() {
    return this._chatOpen;
  },

  set chatOpen(status) {
    this.set("_chatOpen", status);
    this._updatePresence();
  },

  _updatePresence() {
    next(() => {
      if (this.fullScreenChatOpen || this.chatOpen) {
        this.presenceChannel.enter({ activeOptions: CHAT_ONLINE_OPTIONS });
      } else {
        this.presenceChannel.leave();
      }
    });
  },

  getDocumentTitleCount() {
    return this.chatNotificationManager.shouldCountChatInDocTitle()
      ? this.unreadUrgentCount
      : 0;
  },

  _channelObject() {
    return {
      publicChannels: this.publicChannels,
      directMessageChannels: this.directMessageChannels,
    };
  },

  async isChannelFollowed(channel) {
    return this.getChannelBy("id", channel.id);
  },

  getChannels() {
    return new Promise((resolve) => {
      if (this.hasFetchedChannels) {
        return resolve(this._channelObject());
      }

      if (!this._fetchingChannels) {
        this._fetchingChannels = this._refreshChannels().finally(
          () => (this._fetchingChannels = null)
        );
      }

      this._fetchingChannels.then(() => resolve(this._channelObject()));
    });
  },

  forceRefreshChannels() {
    this.set("hasFetchedChannels", false);
    this._unsubscribeFromAllChatChannels();
    return this.getChannels();
  },

  _refreshChannels() {
    return new Promise((resolve) => {
      this.setProperties({
        loading: true,
        allChannels: [],
      });
      this.currentUser.set("chat_channel_tracking_state", {});
      ajax("/chat/chat_channels.json").then((channels) => {
        this.setProperties({
          publicChannels: A(
            this.sortPublicChannels(
              channels.public_channels.map((channel) =>
                this.processChannel(channel)
              )
            )
          ),
          // We don't need to sort direct message channels, as the channel list
          // uses a computed property to keep them ordered by `updated_at`.
          directMessageChannels: A(
            channels.direct_message_channels.map((channel) =>
              this.processChannel(channel)
            )
          ),
          hasFetchedChannels: true,
          loading: false,
        });
        const idToTitleMap = {};
        this.allChannels.forEach((c) => {
          idToTitleMap[c.id] = c.title;
        });
        this.set("idToTitleMap", idToTitleMap);
        this.presenceChannel.subscribe(channels.global_presence_channel_state);
        this.userChatChannelTrackingStateChanged();
        this.appEvents.trigger("chat:refresh-channels");
        resolve(this._channelObject());
      });
    });
  },

  async getChannelBy(key, value) {
    return this.getChannels().then(() => {
      if (!isNaN(value)) {
        value = parseInt(value, 10);
      }
      return (this.allChannels || []).findBy(key, value);
    });
  },

  getIdealFirstChannelId() {
    // When user opens chat we need to give them the 'best' channel when they enter.
    // Look for public channels with mentions. If one exists, enter that.
    // Next best is a DM channel with unread messages.
    // Next best is a public channel with unread messages.
    return this.getChannels().then(() => {
      // Defined in order of significance.
      let publicChannelWithMention,
        dmChannelWithUnread,
        publicChannelWithUnread,
        publicChannel,
        dmChannel;

      for (const [channel, state] of Object.entries(
        this.currentUser.chat_channel_tracking_state
      )) {
        if (state.chatable_type === "DirectMessageChannel") {
          if (!dmChannelWithUnread && state.unread_count > 0) {
            dmChannelWithUnread = channel;
          } else if (!dmChannel) {
            dmChannel = channel;
          }
        } else {
          if (!publicChannelWithMention && state.unread_mentions > 0) {
            publicChannelWithMention = channel;
            break; // <- We have a public channel with a mention. Break and return this.
          } else if (!publicChannelWithUnread && state.unread_count > 0) {
            publicChannelWithUnread = channel;
          } else if (!publicChannel) {
            publicChannel = channel;
          }
        }
      }
      return (
        publicChannelWithMention ||
        dmChannelWithUnread ||
        publicChannelWithUnread ||
        publicChannel ||
        dmChannel
      );
    });
  },

  sortPublicChannels(channels) {
    return channels.sort((a, b) => {
      const typeA = PUBLIC_CHANNEL_SORT_PRIOS[a.chatable_type];
      const typeB = PUBLIC_CHANNEL_SORT_PRIOS[b.chatable_type];
      if (typeA === typeB) {
        return a.title.localeCompare(b.title);
      } else {
        return typeA < typeB ? -1 : 1;
      }
    });
  },

  sortDirectMessageChannels(channels) {
    return channels.sort((a, b) => {
      const unreadCountA =
        this.currentUser.chat_channel_tracking_state[a.id]?.unread_count || 0;
      const unreadCountB =
        this.currentUser.chat_channel_tracking_state[b.id]?.unread_count || 0;
      if (unreadCountA === unreadCountB) {
        return new Date(a.updated_at) > new Date(b.updated_at) ? -1 : 1;
      } else {
        return unreadCountA > unreadCountB ? -1 : 1;
      }
    });
  },

  getIdealFirstChannelIdAndTitle() {
    return this.getIdealFirstChannelId().then((channelId) => {
      if (!channelId) {
        return;
      }
      return {
        id: channelId,
        title: this.idToTitleMap[channelId],
      };
    });
  },

  async openChannelAtMessage(channelId, messageId) {
    let channel = await this.getChannelBy("id", channelId);
    if (channel) {
      return this._openFoundChannelAtMessage(channel, messageId);
    }

    return ajax(`/chat/chat_channels/${channelId}`).then((response) => {
      this.router.transitionTo(
        "chat.channel",
        response.chat_channel.id,
        response.chat_channel.title,
        {
          queryParams: { messageId },
        }
      );
    });
  },

  _openFoundChannelAtMessage(channel, messageId) {
    if (
      this.router.currentRouteName === "chat.channel" &&
      this.router.currentRoute.params.channelTitle === channel.title
    ) {
      this._fireOpenMessageAppEvent(messageId);
    } else if (
      Site.currentProp("mobileView") ||
      this.router.currentRouteName === "chat" ||
      this.router.currentRouteName === "chat.channel" ||
      this.currentUser.chat_isolated
    ) {
      this.router.transitionTo("chat.channel", channel.id, channel.title, {
        queryParams: { messageId: messageId },
      });
    } else {
      this._fireOpenFloatAppEvent(channel, messageId);
    }
  },

  _fireOpenFloatAppEvent(channel, messageId) {
    this.appEvents.trigger("chat:open-channel-at-message", channel, messageId);
  },

  _fireOpenMessageAppEvent(messageId) {
    this.appEvents.trigger("chat-live-pane:highlight-message", messageId);
  },

  async startTrackingChannel(channel) {
    const existingChannel = await this.getChannelBy("id", channel.id);
    if (existingChannel) {
      return; // User is already tracking this channel. return!
    }

    const isDirectMessageChannel =
      channel.chatable_type === "DirectMessageChannel";
    const existingChannels = isDirectMessageChannel
      ? this.directMessageChannels
      : this.publicChannels;

    existingChannels.pushObject(this.processChannel(channel));
    this.currentUser.chat_channel_tracking_state[channel.id] = {
      unread_count: 0,
      unread_mentions: 0,
      chatable_type: channel.chatable_type,
    };
    this.userChatChannelTrackingStateChanged();
    if (!isDirectMessageChannel) {
      this.set("publicChannels", this.sortPublicChannels(this.publicChannels));
    }
    this.appEvents.trigger("chat:refresh-channels");
  },

  async stopTrackingChannel(channel) {
    const existingChannel = await this.getChannelBy("id", channel.id);
    if (existingChannel) {
      this.forceRefreshChannels();
    }
  },

  _subscribeToChannelEdits() {
    this.messageBus.subscribe("/chat/channel-edits", (busData) => {
      this.getChannelBy("id", busData.chat_channel_id).then((channel) => {
        if (channel) {
          channel.setProperties({
            title: busData.name,
            description: busData.description,
          });
        }
      });
    });
  },

  _unsubscribeFromChannelEdits() {
    this.messageBus.unsubscribe("/chat/channel-edits");
  },

  _subscribeToNewDmChannelUpdates() {
    this.messageBus.subscribe("/chat/new-direct-message-channel", (busData) => {
      this.startTrackingChannel(busData.chat_channel);
    });
  },

  _unsubscribeFromNewDmChannelUpdates() {
    this.messageBus.unsubscribe("/chat/new-direct-message-channel");
  },

  _subscribeToSingleUpdateChannel(channel) {
    if (channel.muted) {
      return;
    }

    if (channel.chatable_type !== "DirectMessageChannel") {
      this._subscribeToMentionChannel(channel);
    }

    this.messageBus.subscribe(`/chat/${channel.id}/new-messages`, (busData) => {
      if (busData.user_id === this.currentUser.id) {
        // User sent message, update tracking state to no unread
        this.currentUser.chat_channel_tracking_state[
          channel.id
        ].chat_message_id = busData.message_id;
      } else {
        // Message from other user. Increment trackings state
        const trackingState = this.currentUser.chat_channel_tracking_state[
          channel.id
        ];
        if (busData.message_id > (trackingState.chat_message_id || 0)) {
          trackingState.unread_count = trackingState.unread_count + 1;
        }
      }
      this.userChatChannelTrackingStateChanged();

      // Update updated_at timestamp for channel if direct message
      const dmChatChannel = (this.directMessageChannels || []).findBy(
        "id",
        parseInt(channel.id, 10)
      );
      if (dmChatChannel) {
        dmChatChannel.set("updated_at", new Date());
      }
    });
  },

  _subscribeToMentionChannel(channel) {
    this.messageBus.subscribe(`/chat/${channel.id}/new-mentions`, () => {
      const trackingState = this.currentUser.chat_channel_tracking_state[
        channel.id
      ];
      if (trackingState) {
        trackingState.unread_mentions =
          (trackingState.unread_mentions || 0) + 1;
        this.userChatChannelTrackingStateChanged();
      }
    });
  },

  async unfollowChannel(channel) {
    return ajax(`/chat/chat_channels/${channel.id}/unfollow`, {
      method: "POST",
    })
      .then(async () => {
        this._unsubscribeFromChatChannel(channel);
        return this._refreshChannels().then(() => {
          return this.getIdealFirstChannelIdAndTitle().then((channelInfo) => {
            if (
              channel.id !==
              this.router.currentRoute.attributes?.chatChannel?.id
            ) {
              return;
            }

            if (channelInfo) {
              return this.router.transitionTo(
                "chat.channel",
                channelInfo.id,
                channelInfo.title
              );
            } else {
              return this.router.transitionTo("chat");
            }
          });
        });
      })
      .catch(popupAjaxError);
  },

  _unsubscribeFromAllChatChannels() {
    (this.allChannels || []).forEach((channel) => {
      this._unsubscribeFromChatChannel(channel);
    });
  },

  _unsubscribeFromChatChannel(channel) {
    this.messageBus.unsubscribe(`/chat/${channel.id}/new-messages`);
    if (channel.chatable_type !== "DirectMessageChannel") {
      this.messageBus.unsubscribe(`/chat/${channel.id}/new-mentions`);
    }
  },

  _subscribeToUserTrackingChannel() {
    this.messageBus.subscribe(
      `/chat/user-tracking-state/${this.currentUser.id}`,
      (busData, _, messageId) => {
        const lastId = this.lastUserTrackingMessageId;

        // we don't want this state to go backwards, only catch
        // up if messages from messagebus were missed
        if (!lastId || messageId > lastId) {
          this.lastUserTrackingMessageId = messageId;
        }

        // we are too far out of sync, we should resync everything.
        // this will trigger a route transition and blur the chat input
        if (lastId && messageId > lastId + 1) {
          return this.forceRefreshChannels();
        }

        const trackingState = this.currentUser.chat_channel_tracking_state[
          busData.chat_channel_id
        ];
        if (trackingState) {
          trackingState.chat_message_id = busData.chat_message_id;
          trackingState.unread_count = 0;
          trackingState.unread_mentions = 0;
          this.userChatChannelTrackingStateChanged();
        }
      }
    );
  },

  _unsubscribeFromUserTrackingChannel() {
    this.messageBus.unsubscribe(
      `/chat/user-tracking-state/${this.currentUser.id}`
    );
  },

  resetTrackingStateForChannel(channelId) {
    const trackingState = this.currentUser.chat_channel_tracking_state[
      channelId
    ];
    if (trackingState) {
      trackingState.unread_count = 0;
      this.userChatChannelTrackingStateChanged();
    }
  },

  userChatChannelTrackingStateChanged() {
    this._recalculateUnreadMessages();
  },

  _recalculateUnreadMessages() {
    let unreadPublicCount = 0;
    let unreadUrgentCount = 0;
    let headerNeedsRerender = false;

    Object.values(this.currentUser.chat_channel_tracking_state).forEach(
      (state) => {
        if (state.muted) {
          return;
        }

        if (state.chatable_type === "DirectMessageChannel") {
          unreadUrgentCount += state.unread_count || 0;
        } else {
          unreadUrgentCount += state.unread_mentions || 0;
          unreadPublicCount += state.unread_count || 0;
        }
      }
    );

    let hasUnreadPublic = unreadPublicCount > 0;
    if (hasUnreadPublic !== this.hasUnreadMessages) {
      headerNeedsRerender = true;
      this.set("hasUnreadMessages", hasUnreadPublic);
    }

    if (unreadUrgentCount !== this.unreadUrgentCount) {
      headerNeedsRerender = true;
      this.set("unreadUrgentCount", unreadUrgentCount);
    }

    this.currentUser.notifyPropertyChange("chat_channel_tracking_state");
    if (headerNeedsRerender) {
      this.appEvents.trigger("chat:rerender-header");
      this.appEvents.trigger("notifications:changed");
    }
  },

  processChannel(channel) {
    channel = EmberObject.create(channel);
    this._subscribeToSingleUpdateChannel(channel);
    this._updateUserTrackingState(channel);
    this.allChannels.push(channel);
    return channel;
  },

  _updateUserTrackingState(channel) {
    this.currentUser.chat_channel_tracking_state[channel.id] = {
      muted: channel.muted,
      unread_count: channel.unread_count,
      unread_mentions: channel.unread_mentions,
      chatable_type: channel.chatable_type,
      chat_message_id: channel.last_read_message_id,
    };
  },

  setDraftForChannel(channelId, draft, replyToMsg = null) {
    this._draftStore.setObject({ key: channelId, value: draft, replyToMsg });
  },

  getDraftForChannel(channelId) {
    return (
      this._draftStore.getObject(channelId) || {
        value: "",
        uploads: [],
        replyToMsg: null,
      }
    );
  },

  addToolbarButton(toolbarButton) {
    addChatToolbarButton(toolbarButton);
  },
});

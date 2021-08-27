export const messageContents = ["Hello world", "What up"];
export const siteChannel = {
  chat_channel: {
    chat_channels: [],
    chatable: null,
    chatable_id: -1,
    chatable_type: "Site",
    chatable_url: "http://localhost:3000",
    id: 9,
    title: "Site",
  },
};
export const directMessageChannel = {
  chat_channel: {
    chat_channels: [],
    chatable: {
      users: [
        { id: 1, username: "markvanlan" },
        { id: 2, username: "hawk" },
      ],
    },
    chatable_id: 58,
    chatable_type: "DirectMessageChannel",
    chatable_url: null,
    id: 75,
    title: "@hawk",
  },
};

export const chatChannels = {
  public_channels: [
    siteChannel.chat_channel,
    {
      id: 7,
      chatable_id: 1,
      chatable_type: "Category",
      chatable_url: "/c/uncategorized/1",
      title: "Uncategorized",
      chatable: {
        id: 1,
        name: "Uncategorized",
        color: "0088CC",
        text_color: "FFFFFF",
        slug: "uncategorized",
      },
      chat_channels: [
        {
          id: 4,
          chatable_id: 12,
          chatable_type: "Topic",
          chatable_url: "http://localhost:3000/t/small-action-testing-topic/12",
          title: "Small action - testing topic",
          chatable: {
            id: 12,
            title: "Small action - testing topic",
            fancy_title: "Small action - testing topic",
            slug: "small-action-testing-topic",
            posts_count: 1,
          },
          chat_channels: [],
        },
        {
          id: 11,
          chatable_id: 80,
          chatable_type: "Topic",
          chatable_url:
            "http://localhost:3000/t/coolest-thing-you-have-seen-today/80",
          title: "Coolest thing you have seen today",
          chatable: {
            id: 80,
            title: "Coolest thing you have seen today",
            fancy_title: "Coolest thing you have seen today",
            slug: "coolest-thing-you-have-seen-today",
            posts_count: 100,
          },
          chat_channels: [],
        },
      ],
    },
  ],
  direct_message_channels: [directMessageChannel.chat_channel],
};

export const chatView = {
  topic_chat_view: {
    can_chat: true,
    can_flag: true,
    can_delete_self: true,
    can_delete_others: false,
    messages: [
      {
        id: 174,
        message: messageContents[0],
        action_code: null,
        created_at: "2021-07-20T08:14:16.950Z",
        flag_count: 0,
        user: {
          id: 1,
          username: "markvanlan",
          name: null,
          avatar_template: "/letter_avatar_proxy/v4/letter/m/48db29/{size}.png",
        },
      },
      {
        id: 175,
        message: messageContents[1],
        action_code: null,
        created_at: "2021-07-20T08:14:22.043Z",
        in_reply_to_id: 174,
        flag_count: 0,
        user: {
          id: 2,
          username: "hawk",
          name: null,
          avatar_template: "/letter_avatar_proxy/v4/letter/m/48db29/{size}.png",
        },
      },
    ],
  },
};
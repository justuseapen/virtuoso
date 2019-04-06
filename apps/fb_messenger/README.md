FbMessenger FbMessenger Client
===========================
Provides message receiving and sending capabilities for FbMessenger projects.

# Facebook Pages and Applications
To communicate with Facebook you'll need both A Facebook Page and Facebook Application. The Page is basically the user facing entity that's accessible publically and the Application represents your application.

1. [Create a Facebook Page](https://www.facebook.com/pages/creation/)
2. [Create a Facebook App]( https://developers.facebook.com/apps/ )
3. Generate a `page_access_token` and put it in your `dev.secret.exs` like
```
config :fb_messenger,
  page_access_token: "TOKENGOESHERE"
```

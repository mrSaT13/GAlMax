<!--
SPDX-FileCopyrightText: 2026 Contributors to GAlMax
SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Privacy

GAlMax (`im.galmax.app`) is available on Android and Web. Based on FluffyChat — a Matrix client.

*   [Matrix](#matrix)
*   [Database](#database)
*   [Encryption](#encryption)
*   [App Permissions](#app-permissions)
*   [Push Notifications](#push-notifications)
*   [PlayStore Safety Standards](#playstore-safety)

## <a id="matrix" href="#matrix">#</a> Matrix
GAlMax uses the Matrix protocol. This means that GAlMax is just a client that can be connected to any compatible Matrix server. The respective data protection agreement of the server selected by the user then applies.

For convenience, one or more servers are set as default that the developers consider trustworthy. Before the first communication, users are informed which server they are connecting to.

GAlMax only communicates with the selected server and with [OpenStreetMap](https://openstreetmap.org) to display maps.

More information is available at: [https://matrix.org](https://matrix.org)

## <a id="database" href="#database">#</a> Database
GAlMax caches some data received from the server in a local sqflite database on the device of the user. On web indexedDB is used. GAlMax always tries to encrypt the database by using SQLCipher and stores the encryption key in the [Secure Storage](https://pub.dev/packages/flutter_secure_storage) of the device.

More information is available at: [https://pub.dev/packages/sqflite](https://pub.dev/packages/sqflite) and [https://pub.dev/packages/sqlcipher_flutter_libs](https://pub.dev/packages/sqlcipher_flutter_libs)

## <a id="encryption" href="#encryption">#</a> Encryption
All communication of substantive content between GAlMax and any server is done in secure way, using transport encryption to protect it.

GAlMax also uses End-To-End-Encryption by using [Vodozemac](https://github.com/matrix-org/vodozemac) and enables it by default for private chats.

## <a id="app-permissions" href="#app-permissions">#</a> App Permissions

The permissions are the same on Android and iOS but may differ in the name. This are the Android Permissions:

#### Internet Access
GAlMax needs to have internet access to communicate with the Matrix Server.

#### Vibrate
GAlMax uses vibration for local notifications. More informations about this are at the used package:
[https://pub.dev/packages/flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications)

#### Record Audio
GAlMax can send voice messages in a chat and therefore needs to have the permission to record audio.

#### Write External Storage
The user is able to save received files and therefore app needs this permission.

#### Read External Storage
The user is able to send files from the device's file system.

#### Location
GAlMax makes it possible to share the current location via the chat. When the user shares their location, GAlMax uses the device location service and sends the geo-data via Matrix.

## <a id="push-notifications" href="#push-notifications">#</a> Push Notifications
GAlMax uses the Firebase Cloud Messaging service for push notifications on Android. This takes place in the following steps:
1. The Matrix server sends the push notification to the GAlMax Push Gateway (`https://push.galmax.im`)
2. The GAlMax Push Gateway forwards the message in a different format to Firebase Cloud Messaging
3. Firebase Cloud Messaging waits until the user's device is online again
4. The device receives the push notification from Firebase Cloud Messaging and displays it as a notification

`event_id_only` is used as the format for the push notification. A typical push notification therefore only contains:
- Event ID
- Room ID
- Unread Count
- Information about the device that is to receive the message

A typical push notification could look like this:
```json
{
  "notification": {
    "event_id": "$3957tyerfgewrf384",
    "room_id": "!slw48wfj34rtnrf:example.com",
    "counts": {
      "unread": 2,
      "missed_calls": 1
    },
    "devices": [
      {
        "app_id": "im.galmax.app",
        "pushkey": "V2h5IG9uIGVhcnRoIGRpZCB5b3UgZGVjb2RlIHRoaXM/",
        "pushkey_ts": 12345678,
        "data": {
          "client_name": "<random-identifier-for-the-client-in-case-of-multi-account-usage>"  
        },
        "tweaks": {
          "sound": "bing"
        }
      }
    ]
  }
}
```

GAlMax sets the `event_id_only` flag at the Matrix Server. This server is then responsible to send the correct data.


# <a id="playstore-safety" href="#playstore-safety">#</a> Explanation of GAlMax's Compliance with Google Play Store's Safety Standards

GAlMax is committed to promoting a safe and respectful environment for all users. As a Matrix client, GAlMax connects users to various Matrix servers. Please note that GAlMax does not host or manage any servers directly, and as such, we do not have the capability to enforce content moderation or deletion within the app itself.

To enhance user safety and help protect against the sexual abuse and exploitation of children, GAlMax enables users to report inappropriate content directly to server administrators.

#### Reporting Content or Users:

1. Mark a message in the chat: Tap and hold the message you wish to report.
2. Report the message: Select the "Report" option.
3. Provide a reason and score: Enter the reason for reporting and assign a score from 1-100 to indicate how offensive the content is.
4. Notification to admin: The server administrator will be notified of the reported content.

In addition to reporting messages, users can also report other users following a similar process.

We encourage server administrators to adhere to strict safety standards and provide mechanisms for addressing and moderating inappropriate content. For more information on the Matrix protocol and its safety standards, please refer to the following link: https://matrix.org/docs/older/moderation/

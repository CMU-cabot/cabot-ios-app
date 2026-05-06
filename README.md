[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
# cabot-app

- CaBot app is a bluetooth peripheral app of CaBot.
- The user need to specify a **team name** in the setting view
  - The app will advertise BLE service as **`CaBot-<team name>`** when it is in foreground
- CaBot's ros1 system needs to be launched with `-e <team name>` option
  - CaBot scans the name and tries to connect when found
- There are multiple IN/OUT characteristics (subject to be changed)
- The map screen incorporates a Java script file, which is copied by a script at build time.
  - The java script file is the 3D Visualization Library for use with the ROS JavaScript Libraries
  - The map screen receives data using web sockets.
  - For more information on ros3djs, check [here](https://github.com/RobotWebTools/ros3djs/).

## BLE spec

- Service UUID: `35CE0000-5E89-4C0D-A3F6-8A6A507C1BF1`
- characteristics

type|ID|IN/OUT|data|description
---|---|---|---|---
version|0x00|IN|text|protocol version
manage|0x01|OUT|text|send command to control system (reboot, restart, etc)
device status|0x02|IN|text|device status JSON
system status|0x03|IN|text|system status JSON
battery status|0x04|IN|text|battery status JSON
log|0x05|OUT|text|send log text
summons|0x010|OUT|text|set the destination of the robot (summon mode), specify a node id
destination|0x11|OUT|text|set the destination of the robot (normal mode), specify a node id or `__cancel__` for cancel
speech|0x30|IN|text|speak input text
navi|0x40|IN|text|navigation status, next or arrived, sound, content, subtour
heart_beat|0x9999|OUT|text|send heart beat every second

## How to build

```
$ open CaBot.xcworkspace and build
```

### Model data structure
```
Main Bundle
 | - Resource
     | - Resource_DIR
         | - _metadata.yaml
         | - ...
     | - <any subdir>
         | - Resource_DIR
             | - _metadata.yaml
             | - ...
```

### Metadata format
```yaml
name: I18NText                       # this should be unique among Resource_DIRs
language: LanguageCode?              # optional, if specified, use the language instead of the system setting
conversation: Source<Conversation>?  # optional, conversation source
destinations: Source<Destinations>?  # optional, destinations source
tours: Source<Tours>?                # optional, tours source
location:
  ibeacon-uuid: [String]             # for beacon scanning
  lat: Float                         # to determine location automatically
  lng: Float                         #
  radius: Int                        # in meters
```

### I18NText format
`<key>` can be any property string such as `name` and `title`.

```
<key>: text           # text for the system language
<key>-ja: text        # text for the language specified by the 2-characters lang code (ja in this case)
<key>-ja-pron: text   # reading text for the language specified by the 2-characters lang code (ja in this case)
```

### Source format
```yaml
type: String (local / remote)
src: String (relative path / URL)
```

### Conversation format
- JavaScript to handle conversation
- it needs to implement `function getResponse(request)`

```
custom global objects
Bundle.loadYaml       : returns a list of destination from a specified yaml file
Console.log           : print log
Bluetooth.scanBeacons : scan beacons
Device.type           : device type like iPhone13,3
Device.id             : device vendor uuid
HTTPS.postJSON        : post JSON to a host (not implemented yet)
View.showModalWaitingWithMessage : show modal wait and a message
View.hideModalWaiting            : hide the modal wait
View.alert                       : show an alert with title and message
```

### Destinations format
```
[Destination | DestinationRef | DestinationSource]
```

#### Destination format
```yaml
title: I18NText
value: String
startMessage: Source?
arriveMessages: [Source]?
content: Source?
waitingDestination: DestinationRef
subtour: <file name>/<id of a tour>
```

#### DestinationRef
```yaml
ref: <file name>/<value of a destination>
if other keys of the Destination format are specified, it will override the reference destination
```

#### DestinationSource format
```
title: I18NText
file:  Source?
```

### Tours format
```
[Tour]
```

#### Tour format
```
id: String
title: I18NText
introduction: I18NText          # brief description of the tour
destinations: Destinations
```

## Zoom SDK setup

Before opening Xcode for the `CaBot-User` target, download the Zoom Meeting SDK binaries:

```bash
./setup_zoom_sdk.sh
```

This downloads the `zoom-sdk-7.0.2.34511` release asset from this repository and installs it into `Vendor/Zoom`. To replace an existing local copy, run:

```bash
./setup_zoom_sdk.sh --force
```

If `Vendor/Zoom` is missing, the `CaBot-User` build also runs this script automatically.

## Zoom Meeting SDK JWT

- Install the Zoom SDK binaries with `./setup_zoom_sdk.sh`.
- Set `ZoomMeetingSDKJWTURL` in `CaBot/Info.plist`.
- The endpoint is fetched with `GET` when joining a meeting.
- The response can be either raw JWT text or JSON such as `{"jwt":"<token>"}`.

Example `Info.plist` entry:

```xml
<key>ZoomMeetingSDKJWTURL</key>
<string>https://your-server.example.com/zoom/sdk/jwt</string>
```

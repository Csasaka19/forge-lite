# Mobile-Specific Features

How to use the camera, biometrics, push, share sheet, deep links, background work, and geofencing on React Native + Expo. Read before reaching into native APIs.

## Stack

Default to **Expo SDK 52+**. Every API below has a managed Expo module — no native code editing required.

## Camera & Photo Library

```bash
npx expo install expo-camera expo-image-picker
```

### Picker (Choose from Gallery)

```tsx
import * as ImagePicker from 'expo-image-picker'

async function pickImage() {
  const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync()
  if (status !== 'granted') return

  const result = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: ImagePicker.MediaTypeOptions.Images,
    quality: 0.8,
    allowsEditing: true,
  })
  if (!result.canceled) await upload(result.assets[0])
}
```

### Camera (Live View)

```tsx
import { CameraView, useCameraPermissions } from 'expo-camera'

function CameraScreen() {
  const [permission, requestPermission] = useCameraPermissions()
  const ref = useRef<CameraView>(null)

  if (!permission?.granted) {
    return <Button title="Grant camera" onPress={requestPermission} />
  }

  return (
    <CameraView ref={ref} style={{ flex: 1 }} facing="back">
      <Button title="Capture" onPress={async () => {
        const photo = await ref.current?.takePictureAsync({ quality: 0.8 })
        if (photo) onCaptured(photo.uri)
      }} />
    </CameraView>
  )
}
```

### Rules

- **Request permission in context.** Don't ask on launch — ask when the user taps "Take photo."
- **Compress before upload.** `quality: 0.8` is usually plenty for photos; further resize with `expo-image-manipulator`.
- **Handle denial gracefully.** Show "Open Settings" if denied, not an angry alert.

## QR / Barcode Scanning

`expo-barcode-scanner` is being deprecated in favor of `expo-camera`'s built-in scanner:

```tsx
import { CameraView } from 'expo-camera'

<CameraView
  style={{ flex: 1 }}
  barcodeScannerSettings={{ barcodeTypes: ['qr', 'ean13', 'code128'] }}
  onBarcodeScanned={({ data, type }) => {
    if (data === lastScanned.current) return       // de-dupe
    lastScanned.current = data
    onScan({ data, type })
  }}
/>
```

### Rules

- **De-dupe rapid scans.** The camera fires `onBarcodeScanned` continuously while the code is in frame.
- **Validate the payload.** A QR can contain anything. If you expect a URL, verify the format and domain.
- **Visual feedback** — flash a frame, vibrate, play a tone. Confirms to the user.
- **Cancellation** — let the user dismiss the scanner. Always include a close button.

## Biometric Auth

```bash
npx expo install expo-local-authentication
```

```ts
import * as LocalAuthentication from 'expo-local-authentication'

async function unlockWithBiometric() {
  const hardware = await LocalAuthentication.hasHardwareAsync()
  const enrolled = await LocalAuthentication.isEnrolledAsync()
  if (!hardware || !enrolled) return false

  const result = await LocalAuthentication.authenticateAsync({
    promptMessage: 'Unlock your account',
    fallbackLabel: 'Use passcode',
    cancelLabel: 'Cancel',
  })
  return result.success
}
```

### Rules

- **Biometric is a convenience, not a credential.** Pair it with a real session token. Use biometric to unlock a stored token, never as the only auth.
- **Fallback to passcode** — `fallbackLabel`. Users with bad fingerprints or face masks need an out.
- **Store secrets with `expo-secure-store`** — backed by iOS Keychain / Android Keystore. Never plaintext in MMKV or AsyncStorage.

```ts
import * as SecureStore from 'expo-secure-store'

await SecureStore.setItemAsync('refresh-token', token, {
  requireAuthentication: true,    // iOS: gate with biometric
})
```

## Share Sheet

```ts
import { Share } from 'react-native'

await Share.share({
  message: `Check out this machine: ${url}`,
  url,
  title: 'Water Vending',
})
```

For richer share content (multiple files, custom MIME), use `expo-sharing`:

```ts
import * as Sharing from 'expo-sharing'

await Sharing.shareAsync(localFileUri, {
  mimeType: 'application/pdf',
  dialogTitle: 'Save invoice',
})
```

## Deep Linking & Universal Links

Configure in `app.json` at project start — adding later is painful.

```json
{
  "expo": {
    "scheme": "watervending",
    "ios": {
      "associatedDomains": ["applinks:example.com"]
    },
    "android": {
      "intentFilters": [
        {
          "action": "VIEW",
          "autoVerify": true,
          "data": [{ "scheme": "https", "host": "example.com" }],
          "category": ["BROWSABLE", "DEFAULT"]
        }
      ]
    }
  }
}
```

Then Expo Router maps URLs to routes automatically: `https://example.com/machine/42` → `app/machine/[id].tsx`.

### Handling at Runtime

```ts
import * as Linking from 'expo-linking'

useEffect(() => {
  const sub = Linking.addEventListener('url', ({ url }) => handle(url))
  Linking.getInitialURL().then((url) => url && handle(url))
  return () => sub.remove()
}, [])
```

### Verify the Host Page

For Universal Links / App Links to work, host **Apple App Site Association** + **Android assetlinks.json** at the right URLs. Without these, the URL opens in Safari/Chrome instead of your app.

```
https://example.com/.well-known/apple-app-site-association
https://example.com/.well-known/assetlinks.json
```

Test with Apple's `swcutil` and Google's Asset Links Tester.

## Local Notifications

```bash
npx expo install expo-notifications
```

For scheduling reminders that don't need a server:

```ts
import * as Notifications from 'expo-notifications'

await Notifications.scheduleNotificationAsync({
  content: {
    title: 'Time to refill',
    body: 'Your machine is low on water',
    sound: 'default',
  },
  trigger: { seconds: 60 * 60 },     // 1 hour from now
})

// Or at a specific time
await Notifications.scheduleNotificationAsync({
  content: { title: 'Daily report' },
  trigger: { hour: 9, minute: 0, repeats: true },
})
```

### Rules

- **Request permission first.** `requestPermissionsAsync()`. Same UX rules as push.
- **Cancel obsolete reminders.** Use returned `identifier` to cancel when the event becomes irrelevant.
- **Android channels** — required for Android 8+. Create at app start.

```ts
await Notifications.setNotificationChannelAsync('reminders', {
  name: 'Reminders',
  importance: Notifications.AndroidImportance.DEFAULT,
})
```

## Background Fetch

For periodic work while the app isn't in foreground:

```bash
npx expo install expo-background-fetch expo-task-manager
```

```ts
import * as TaskManager from 'expo-task-manager'
import * as BackgroundFetch from 'expo-background-fetch'

const BG_TASK = 'sync-orders'

TaskManager.defineTask(BG_TASK, async () => {
  try {
    await syncPendingOrders()
    return BackgroundFetch.BackgroundFetchResult.NewData
  } catch {
    return BackgroundFetch.BackgroundFetchResult.Failed
  }
})

await BackgroundFetch.registerTaskAsync(BG_TASK, {
  minimumInterval: 15 * 60,         // 15 minutes minimum
  stopOnTerminate: false,
  startOnBoot: true,
})
```

### Rules

- **The OS decides when.** Your `minimumInterval` is a floor; iOS rarely runs more often than ~hourly.
- **Be fast.** You have ~30 seconds.
- **Be idempotent.** Background fetches may run after the user has done the same action manually.
- **Don't rely on it for critical sync.** Treat it as a best-effort. Have a foreground sync path too.

## Geofencing

```bash
npx expo install expo-location expo-task-manager
```

```ts
import * as Location from 'expo-location'

const GEOFENCE_TASK = 'geofence'

TaskManager.defineTask(GEOFENCE_TASK, ({ data: { eventType, region }, error }) => {
  if (error) return
  if (eventType === Location.GeofencingEventType.Enter) {
    // Notify user, log analytics
  }
})

await Location.startGeofencingAsync(GEOFENCE_TASK, [
  { identifier: 'kilimani-machine', latitude: -1.29, longitude: 36.79, radius: 100, notifyOnEnter: true, notifyOnExit: false },
])
```

### Rules

- **Request "always" permission** carefully. Background location triggers strict iOS / Android scrutiny; explain why before asking.
- **20 fences max on iOS.** Manage the active set dynamically — load fences near the user, drop distant ones.
- **Use sparingly.** Battery drain. Notify-on-enter only when the geofence is genuinely valuable.
- **Test on a physical device.** Simulators don't fire geofences reliably.

## Haptics

```bash
npx expo install expo-haptics
```

```ts
import * as Haptics from 'expo-haptics'

Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light)
Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success)
```

Subtle haptics on key interactions (long-press, scan success, error) make an app feel native. Don't haptic on every tap.

## Common Mistakes

- **Permission requested on launch.** Denial rate spikes. Ask in context.
- **No fallback when permission denied.** "Camera required" with no way forward. Offer "Open Settings."
- **`Notifications` permission for local reminders forgotten.** Reminders never fire on iOS.
- **Deep links added after launch.** Have to refactor every navigation entry point. Plan at scaffold time.
- **No `apple-app-site-association` / `assetlinks.json`.** Universal links don't work; fall through to the browser.
- **`Sharing.shareAsync` on a remote URL.** Throws — Expo `Sharing` is for local files. Download first or use `Share`.
- **Geofencing without "always" location permission.** Doesn't fire in background. Be honest in the explanation.
- **Background fetch as the only sync path.** OS schedules unpredictably. Always have a foreground path.
- **Camera component without `flex: 1` parent.** Renders at 0×0.
- **Plaintext refresh tokens in MMKV.** XSS-equivalent on rooted devices. Use `expo-secure-store`.
- **Biometric without fallback.** User with no enrolled biometric is locked out. Always offer passcode / password.
- **QR scanner firing per frame, processing each one.** UI freezes. De-dupe and debounce.
- **Local notifications without channels on Android.** Silently dropped.
- **Long task in background fetch.** Killed by OS. Keep under 30s.
- **Deep link handler runs before auth is ready.** Race. Queue the URL until auth resolves.

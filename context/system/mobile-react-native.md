# Mobile: React Native

How to build mobile apps with React Native + Expo. Read before scaffolding a mobile app or adding native functionality.

## Decision Tree: When to Use React Native

| You need | Pick |
|---|---|
| iOS + Android with one codebase, JavaScript team | **React Native + Expo** |
| iOS only, deep platform integration, premium polish | **Swift + SwiftUI** |
| Android only, deep platform integration | **Kotlin + Jetpack Compose** |
| Cross-platform, prefer single binary, willing to learn Dart | **Flutter** |
| Just a mobile-shaped website, no app store presence | **PWA** (see `pwa-offline.md`) |
| Native modules / no JS team / heavy 3D / AR | **Native** (Swift/Kotlin) |

React Native is the right choice when:
- You already have a React/TypeScript team.
- The app is form-heavy, list-heavy, or content-heavy (most apps).
- You need to ship to both stores without doubling the team.

Skip it for: real-time 3D games, heavy CV/AR, deeply OS-integrated apps (system widgets, share sheets that go far beyond defaults).

## Start with Expo

**Always start with Expo.** Bare React Native is appropriate only after you've hit an Expo-specific wall.

```bash
npx create-expo-app@latest my-app --template tabs
cd my-app
npx expo start
```

- **Expo SDK 52+** required for the current Reanimated 3, Hermes default, and New Architecture support.
- **Managed workflow** (default) — Expo handles native build config. Use prebuild (`npx expo prebuild`) only when you need a config plugin or custom native module.
- **EAS** (Expo Application Services) for builds and submissions — replaces hand-rolled fastlane/Xcode workflows.

## Project Structure

Expo Router uses file-based routing — file paths become routes.

```
app/
├── _layout.tsx              # root layout (providers, fonts)
├── (tabs)/
│   ├── _layout.tsx          # tab bar
│   ├── index.tsx            # home
│   ├── search.tsx
│   └── profile.tsx
├── machine/
│   └── [id].tsx             # dynamic route /machine/123
├── (auth)/
│   ├── _layout.tsx
│   ├── login.tsx
│   └── signup.tsx
└── +not-found.tsx
components/
├── ui/                      # primitives (Button, Card)
└── shared/                  # composed (StatusBadge, MachineCard)
hooks/
lib/
├── api.ts
└── theme.ts
assets/
├── fonts/
└── images/
```

- **Group routes with parentheses**: `(tabs)`, `(auth)` — folder names that don't appear in URLs.
- **Layouts** (`_layout.tsx`) wrap child routes; nest them for shared chrome.
- **Dynamic routes** use `[param].tsx`. Access via `useLocalSearchParams()`.

## Navigation

### Expo Router (default)

```tsx
// app/_layout.tsx
import { Stack } from 'expo-router'

export default function RootLayout() {
  return (
    <Stack>
      <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      <Stack.Screen name="machine/[id]" options={{ title: 'Machine' }} />
      <Stack.Screen name="(auth)" options={{ presentation: 'modal' }} />
    </Stack>
  )
}
```

### Stack vs Tabs vs Drawer

- **Tabs** — top-level sections users switch between often (Home, Search, Profile). Always visible.
- **Stack** — drilling into detail (list → item → edit). Has a back button.
- **Drawer** — secondary navigation, settings, account switching. Hidden by default.

Most apps: tabs at the root, stacks inside each tab. Drawer is rare on modern mobile — favor tabs + a profile/settings screen.

### Linking

```tsx
import { Link, useRouter } from 'expo-router'

<Link href={`/machine/${id}`}>View machine</Link>

const router = useRouter()
router.push(`/machine/${id}`)
router.replace('/login')      // no back stack
router.back()
```

### Deep Linking from Day One

Configure scheme + universal links **at project start**, not later — handling deep links retroactively is painful.

```json
// app.json
{
  "expo": {
    "scheme": "myapp",
    "ios": { "associatedDomains": ["applinks:example.com"] },
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

Expo Router maps URLs to routes automatically: `https://example.com/machine/42` → `app/machine/[id].tsx`.

### Persisting Navigation State

For deep apps where users want to return where they were:

```tsx
// app/_layout.tsx
import { Stack } from 'expo-router'
import * as SplashScreen from 'expo-splash-screen'

// React Navigation persists nav state automatically with `persistNavigationState`
// in standalone use; with Expo Router, use the `unstable_settings` export per layout
// or restore manually with NavigationState.
```

Don't restore navigation that requires auth without re-checking auth first.

## Platform-Specific Code

### Inline Check

```tsx
import { Platform } from 'react-native'

const padding = Platform.OS === 'ios' ? 16 : 12
```

### Per-Platform Files

For divergent components:

```
Button.tsx          # default
Button.ios.tsx      # iOS-specific
Button.android.tsx  # Android-specific
```

Metro picks the right one. Don't fork for trivial differences — use `Platform.select`:

```tsx
const shadow = Platform.select({
  ios: { shadowColor: '#000', shadowOpacity: 0.1, shadowRadius: 4 },
  android: { elevation: 2 },
})
```

### When to Fork

- Different UX paradigms (segmented controls on iOS vs tabs on Android).
- Different native APIs (haptics, biometrics).
- Different platform expectations (back button on Android, swipe-back on iOS).

Don't fork for: padding tweaks, color differences, font sizes — handle inline.

## Performance

### Lists

`FlatList` for any list beyond ~20 items. **Never** `.map()` inside a `ScrollView` for variable-length data.

```tsx
<FlatList
  data={machines}
  keyExtractor={(m) => m.id}
  renderItem={({ item }) => <MachineCard machine={item} />}
  getItemLayout={(_, i) => ({ length: 80, offset: 80 * i, index: i })}
  windowSize={5}
  removeClippedSubviews
  initialNumToRender={10}
  maxToRenderPerBatch={10}
/>
```

- **`getItemLayout`** is the biggest win — skip dynamic measurement when row height is fixed.
- **`windowSize`** controls offscreen render distance. 5 is a good default.
- **`removeClippedSubviews`** drops offscreen views from native hierarchy.

For very long or heterogeneous lists, use **`@shopify/flash-list`** — recycler-based, faster than FlatList for big lists.

### Animations

Use **Reanimated 3** (`react-native-reanimated`) — runs animations on the UI thread.

```tsx
import Animated, { useSharedValue, useAnimatedStyle, withTiming } from 'react-native-reanimated'

const opacity = useSharedValue(0)
const style = useAnimatedStyle(() => ({ opacity: opacity.value }))

<Animated.View style={style} />
opacity.value = withTiming(1, { duration: 300 })
```

For older `Animated`, always pass `useNativeDriver: true` when animating non-layout properties (opacity, transform).

### Engine

**Hermes** is the default and the only choice for production. Smaller bundle, faster startup, better memory. Don't switch to JSC.

### Memoization

`React.memo`, `useMemo`, `useCallback` apply identically to React Native. They matter more here — re-rendering a list of 50 cards on every keystroke drops frames visibly.

## State Management

Same primitives as web:

- **`useState`** / **`useReducer`** for component state.
- **Context** for cross-cutting (theme, auth).
- **Zustand / Jotai** for global UI state.
- **TanStack Query** for server data.

Plus mobile-specific:

- **MMKV** (`react-native-mmkv`) for fast persistent key-value storage. Replaces AsyncStorage in performance-sensitive contexts.

```ts
import { MMKV } from 'react-native-mmkv'

export const storage = new MMKV()
storage.set('user.id', '42')
const id = storage.getString('user.id')
```

MMKV is synchronous and 30× faster than AsyncStorage. Encrypt sensitive values via the `encryptionKey` option.

## Offline

### Storage Choice

- **MMKV** — small key-value (settings, tokens, flags). Default choice.
- **AsyncStorage** — only when a library forces it. Slow, async, deprecated for new code.
- **SQLite via `expo-sqlite` / `op-sqlite`** — relational data, queryable.
- **WatermelonDB** — opinionated offline-first with sync. For complex offline apps.

### Offline-First Pattern

1. Read from local store first; show immediately.
2. Fire network request in background.
3. On success, update local store; UI re-renders.
4. On failure, keep local data, mark as "last updated X ago."

TanStack Query handles most of this with `persistQueryClient`:

```ts
import { persistQueryClient } from '@tanstack/react-query-persist-client'
import { createSyncStoragePersister } from '@tanstack/query-sync-storage-persister'

persistQueryClient({
  queryClient,
  persister: createSyncStoragePersister({ storage: mmkvAdapter }),
})
```

### Detect Connectivity

```tsx
import NetInfo from '@react-native-community/netinfo'

const unsubscribe = NetInfo.addEventListener((state) => {
  setOnline(state.isConnected ?? false)
})
```

Show a subtle banner when offline. Don't block UI — let users browse cached data.

## Push Notifications

### Permission

```ts
import * as Notifications from 'expo-notifications'

async function registerForPush() {
  const { status: existing } = await Notifications.getPermissionsAsync()
  let final = existing
  if (existing !== 'granted') {
    const { status } = await Notifications.requestPermissionsAsync()
    final = status
  }
  if (final !== 'granted') return null

  const token = (await Notifications.getExpoPushTokenAsync({ projectId })).data
  return token
}
```

### Rules

- **Ask in context, not on launch.** Request after the user sees a value: "Want alerts when your order is ready? Allow notifications."
- **Explain before requesting.** A pre-prompt screen with "Why we need this" lifts permission rates.
- **Handle denial gracefully.** Don't beg; surface a settings link.

### Channels (Android)

```ts
await Notifications.setNotificationChannelAsync('orders', {
  name: 'Orders',
  importance: Notifications.AndroidImportance.HIGH,
  vibrationPattern: [0, 250, 250, 250],
  sound: 'default',
})
```

One channel per category. Users can toggle them individually in system settings.

### Foreground Behavior

```ts
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: true,
  }),
})
```

## App Store Deployment

### EAS Build

```bash
npm install -g eas-cli
eas login
eas build:configure
eas build --platform all
```

`eas.json` configures build profiles:

```json
{
  "build": {
    "development": { "developmentClient": true, "distribution": "internal" },
    "preview": { "distribution": "internal", "channel": "preview" },
    "production": { "channel": "production" }
  }
}
```

### Submission Tracks

- **Internal track / TestFlight (internal)** — team only, no review.
- **TestFlight (external) / Closed testing** — beta testers, expedited review.
- **Production** — full review (1–2 days iOS, hours Android).

Always ship to internal first, then expand. Never go straight to production.

### Code Signing

- **iOS**: EAS manages provisioning profiles and certificates automatically. Don't touch Xcode signing unless you must.
- **Android**: EAS generates a keystore; back it up. Losing the keystore means you can't update the app.

### OTA Updates (`expo-updates`)

Push JS bundle updates without going through review.

```bash
eas update --branch production --message "Fix radius filter"
```

- **Only ships JS and assets.** Native code requires a new build.
- **Test on the same SDK version** the production build uses.
- **Channel mismatch** is the most common bug: the build's channel must match the update channel.

Don't use OTA for risky changes; users can't roll back easily.

## Testing

### Unit / Component

**Jest** + **React Native Testing Library**.

```tsx
import { render, screen, fireEvent } from '@testing-library/react-native'

test('shows machine status', () => {
  render(<MachineCard machine={mockMachine} />)
  expect(screen.getByText('Online')).toBeOnTheScreen()
})
```

Configure Jest with `jest-expo` preset.

### E2E

**Maestro** is the modern choice — YAML flows, fast, simulator-friendly.

```yaml
appId: com.example.app
---
- launchApp
- tapOn: "Sign in"
- inputText: "test@example.com"
- tapOn: "Continue"
- assertVisible: "Welcome back"
```

**Detox** is the older choice — more powerful but heavier setup. Reach for it only if Maestro can't express your flows.

### Run on Multiple Devices

Test on:
- Small screen (iPhone SE, 4.7").
- Large screen (Pro Max, tablet).
- Old Android (Android 10+).
- Latest iOS / Android.

Simulators are not enough — get a physical device for the final pass.

## Common Mistakes

- **Bare React Native when Expo would work.** Native config maintenance burns hours weekly. Stay managed.
- **`ScrollView` with 500 items.** All rendered upfront. Use `FlatList` or `FlashList`.
- **No `keyExtractor` or unstable keys.** Re-renders the whole list. Use a stable ID.
- **Animating without `useNativeDriver`.** Animations run on JS thread, drop frames during heavy work.
- **AsyncStorage for everything.** Slow. Use MMKV for hot paths.
- **Requesting notification permission on launch.** Denial rate jumps. Ask in context.
- **Deep linking added later.** Refactor pain. Plan the scheme + Universal Links from the first commit.
- **`Platform.OS` checks scattered through the codebase.** Centralize in a hook or theme.
- **Forgetting `SafeAreaView` / safe-area-context.** Content sits under the notch or home indicator.
- **Building locally with Xcode for releases.** Reproducibility goes out the window. Use EAS.
- **Losing the Android keystore.** App is unupdatable. Back up to a secret manager immediately.
- **OTA-updating native module changes.** Crashes on launch. Native changes require new builds.
- **No physical device testing.** Simulators hide perf and gesture bugs.
- **Trusting JS-thread frame rate from dev mode.** Test release builds — dev is much slower.
- **`Modal` from `react-native` for in-app sheets.** Use `react-native-bottom-sheet` or stack presentation; built-in Modal is dated.
- **Storing JWTs in MMKV unencrypted.** Set an `encryptionKey` for sensitive values, or use `expo-secure-store`.

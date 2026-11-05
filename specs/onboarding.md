# Onboarding

## 1. Description

When a user first opens Muscle Map, they see a welcome screen briefly explaining that the app helps them log workouts, track muscle activity, and work toward fitness goals. They then sign in using their phone number and a six-digit verification code. After signing in, new users set up a basic profile and optionally create their first fitness goal before reaching Home.

The onboarding flow contains four main steps:

1. **Welcome:** Shows the Muscle Map name, a short description, and a Get Started button.
2. **Sign in:** User enters their phone number, receives a six-digit SMS code, and enters it to verify their account. They can resend the code or correct their phone number.
3. **Profile setup:** User enters a display name and chooses their preferred weight unit (lb or kg). Body weight, sex, birth year, and experience level are optional and can be skipped.
4. **First goal:** User can set a strength goal for a specific exercise or a weekly workout frequency goal. This step can be skipped and completed later in the Goals tab.

The final screen has a Get Started button that takes the user to Home. The app should not require users to provide unnecessary personal information or create a goal before they can start tracking workouts.

## 2. Where it fits

Onboarding appears when a user opens the app without a saved authentication token. After successful sign-in, the app fetches the user's profile to determine whether onboarding has already been completed.

A returning user who signs in on a new phone should skip profile setup and goal creation if their account has already completed onboarding. Users who are already signed in should go directly to Home.

If a new user closes the app during onboarding, their progress should be recoverable. After signing in again, the app should return them to any unfinished setup instead of creating a new account.

After onboarding, users land on Home, where they can view their workout activity and navigate to Lift to start logging exercises.

Logging out and handling an invalid authentication token are separate authentication features. If the server returns a 401 response, the app should clear its invalid session and return to sign-in. Previously saved profile information and goals remain attached to the user's account.

## 3. Data and functions

### Server

Onboarding uses the existing authentication and profile endpoints:

- `POST /auth/sms/start` — Sends a six-digit verification code to the user's phone number.
- `POST /auth/sms/verify` — Verifies the code and returns an authentication token.
- `GET /users/me` — Retrieves the user's existing profile after authentication.
- `PUT /users/me` — Saves their profile information and preferred units.

We propose adding an `onboarding_completed` boolean to the user profile, defaulting to false for new accounts. This is more reliable than checking whether a display name exists, especially if users can skip fields. The server would need to support updating this field through `PUT /users/me`.

The flag becomes true only when the user finishes or explicitly skips the optional goal step. This also allows a user who closes the app midway through setup to continue later.

Goal creation uses the endpoints defined in `goals.md`. No separate onboarding endpoint is needed.

### Client

SwiftUI handles the welcome, phone number, verification, profile, and first-goal screens.

The following logic should be separated from the views into the app's testable Swift package:

- Formatting and validating phone numbers before sending them to the server.
- Checking whether verification codes contain six digits.
- Handling verification failures, resending codes, and network errors.
- Reading the saved authentication token.
- Determining whether to show sign-in, onboarding, or Home.
- Converting displayed body weight between lb and kg.
- Saving profile information and handling skipped optional fields.

The app stores authentication tokens securely in the Keychain. Onboarding screens should use the existing design system, including its dark theme, colors, buttons, and spacing.

### Data

User-entered profile fields:

| Field | Required | Description |
|---|---|---|
| Display name | No | Name shown throughout the app |
| Units | Yes | lb or kg, defaulting to lb |
| Body weight | No | Stored in kilograms |
| Sex | No | Optional profile information |
| Birth year | No | Optional profile information |
| Experience | No | Beginner, intermediate, or advanced |

Authentication also uses the user's phone number and verification code. Profile data and onboarding completion should be saved on the server so they are available across devices.

If a user creates a goal during onboarding, it is saved using the same goal model as the Goals tab. Skipping this step leaves the user with no active goals until they create one later.
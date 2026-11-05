# Goals

## 1. Description

The Goals feature lets users set fitness targets and track their progress using workouts logged in Muscle Map. Users can create goals for improving strength in a specific exercise or completing a certain number of workouts each week. Progress updates automatically as workouts are recorded, helping users understand how close they are to their targets.

The first version supports two goal types:

1. **Strength goal:** Reach a target estimated one-rep max (e1RM) for a specific exercise, such as bench pressing 100 kg. The estimate is calculated using the weight and repetitions from logged working sets.
2. **Workout frequency goal:** Complete a target number of workouts per week, such as four workouts every week. The app counts finished workouts during the current calendar week.

Weekly muscle volume and body-weight goals are possible future features, but are outside the initial scope. Muscle volume needs an agreed calculation method, while body-weight goals require a history of weigh-ins rather than only a profile weight.

Users can have up to three active goals at once. Strength goals can have an optional deadline, while workout frequency goals repeat weekly without a fixed end date.

### Goals tab

The Goals tab displays cards for each active goal. Every card shows:

- The goal name and target.
- Current progress based on logged workouts.
- A progress bar and percentage toward the target.
- The remaining amount needed to reach the goal.
- A deadline, if applicable.

Strength goal cards show the current estimated one-rep max compared with the target. Workout frequency cards show how many workouts have been completed during the current week.

Users can tap a card to see more details and can edit or delete goals. The Goals tab also contains a New Goal button and a section for completed strength goals.

When a strength goal is achieved, the app displays a short congratulatory message and marks the goal as completed. Weekly frequency goals show a success message when the weekly target is reached, then reset their weekly progress at the beginning of the next week.

## 2. Where it fits

Users can create their first goal during onboarding or create goals later from the Goals tab. Both entry points use the same goal creation form and save goals to the same server endpoints.

Creating a strength goal involves selecting an exercise from the existing exercise library, entering a target weight, and optionally choosing a deadline.

Creating a workout frequency goal involves choosing the number of workouts to complete per week. A goal can be edited or deleted from its detail screen.

After a user finishes and saves a workout in Lift, their goal progress should update automatically the next time the Goals tab loads. The server calculates progress using the user's workout history rather than storing a separate progress value.

Home may display a small summary of the user's most relevant active goal, linking to the Goals tab. The Body tab continues focusing on muscle activity and recovery rather than duplicating the full Goals interface.

## 3. Data and functions

### Server

The Goals feature requires four new endpoints:

- `GET /goals` — Returns the user's active and completed goals with their calculated progress.
- `POST /goals` — Creates a new goal.
- `PUT /goals/{id}` — Updates an existing goal's target or deadline.
- `DELETE /goals/{id}` — Deletes a goal.

Each goal is linked to its authenticated user. Users cannot view or modify another user's goals.

The server stores the goal definition, but not its calculated progress. Progress is calculated from workout history each time it is requested, following the existing project architecture.

Strength goal progress uses the estimated one-rep max of eligible sets for the selected exercise. For the initial version, use the Epley formula:

`e1RM = weight_kg × (1 + reps / 30)`

For consistency, use completed working or failure sets with a positive external weight and 1–10 repetitions. Take the highest estimate from eligible sets in the user's workout history. Bodyweight-only and timed exercises are excluded from strength goals in the initial version.

Strength progress is calculated as:

`progress = min(100, current_e1rm / target_e1rm × 100)`

If the user has no eligible sets for an exercise, progress is displayed as unavailable rather than assuming a measured one-rep max of zero. Once an eligible estimate reaches the target, the goal is completed.

Workout frequency progress is calculated as:

`progress = min(100, completed_workouts_this_week / weekly_target × 100)`

Only finished workouts count. Each saved workout counts once, regardless of the number of sets it contains. Weeks run from Monday through Sunday using the user's local workout dates.

Goal calculations belong in `server/services/`, while the API handlers handle validation and responses. Goal definitions are saved through the existing Datastore model layer.

### Client

The SwiftUI Goals screens handle displaying goals, creating new ones, and editing or deleting existing goals.

The following logic should be separate from the screens in `MuscleMapKit/GoalsCore`:

- Validating targets and optional deadlines.
- Formatting progress percentages and progress-bar values.
- Converting strength targets between kg and lb.
- Formatting goal descriptions and remaining amounts.
- Displaying completion states and weekly progress messages.
- Handling loading, empty, and error states.

The server remains the source of truth for workout-derived progress. The client should format the returned data without independently recalculating workout history.

### Data

Each goal stores:

| Field | Description |
|---|---|
| id | Unique goal identifier |
| user_id | Owner of the goal |
| type | `strength` or `frequency` |
| exercise_id | Exercise being tracked, for strength goals |
| target | Target e1RM in kg or workouts per week |
| start_date | Date the goal was created |
| deadline | Optional deadline for strength goals |
| created_at | Goal creation timestamp |

The goal ID should be a lowercase UUID generated by the client, consistent with workout and template IDs.

For strength goals, the target is stored in kilograms regardless of the user's preferred units. For frequency goals, the target is a whole number representing workouts per week.

The API also returns calculated fields such as the current value, progress percentage, completion state, and remaining amount. These values are not permanently stored.

Completed strength goals remain visible in the Completed Goals section. Weekly frequency goals stay active and begin tracking a new week every Monday.

### Validation and edge cases

- Users cannot exceed three active goals.
- Strength goals require a valid exercise and a positive target weight.
- Frequency goals accept a target from 1 to 7 workouts per week.
- Deadlines cannot be earlier than the goal's start date.
- Deleting a goal does not delete any workout history.
- Switching between lb and kg changes only how values are displayed.
- Progress bars are capped at 100%, even if the user exceeds the target.
- Empty states encourage users to create a goal or log their first workout.
- If the server cannot load goal data, the app shows an error and a retry option instead of incorrect progress.
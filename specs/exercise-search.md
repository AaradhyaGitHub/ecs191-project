## 1. Description 
- While building a workout you lookup an exercise by name, or if you wanted to see an exercise you've done recently. Based on the results you are able to pick one or more exercises

## 2. What the user does and sees
- A **search box** that searches automatically (with a small delay after you stop typing), and empty box shows you all exercises in the library
- **Muscle group labels** such as Chest, Back or Core. An exercise belongs to the group of its main muscle.
- **Your exercises** with an option to display either your recent or most used exercises, each row shows the name and the last set
- **All exercises** that list all the exercises there are 
- To **Select** just press the row, do the same to unselect. Multiple selctions are allowed, and the buttons should show you how many you got selected
- **Picker** opens when you start an empty workout, add an exercise during a workout, or edit a saved workout. 
- The exercise come from our exercise library

## 3. Data and functions
- For Server (methods and endpoints)
    - `GET /api/v1/exercises?q=…&group=…` - gets sent each time you stop typing in the search type, with the muscle group defined. For now this is public as it holds no personal data, but this may change in the future
    - `GET /api/v1/exercises/mine` - returns your exercises, including the use count, last used date, and last set
    - The logic for matching exercises with groups is in `services/`
- For Client
    - ends the search text and selected muscle group to the server, and asks for your exercises when you are signed in
    - The picker remembers the search text, the muscle group, the Recent/Most used sort, the picked exercises in order, and the superset switch
    - The sorting and picking rules are kept apart from the screen so they can be tested quickly
    - Data: an exercise (name, other names, equipment, muscles) and your history with it (last set, times done, last done)
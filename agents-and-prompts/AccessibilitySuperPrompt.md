# Implementing full accessibility support in an Apple platforms (iOS, iPadOS, MacOS, etc) app

We will implement full accessibility support in the app.
After each phase, have *another* LLM check your work. If you are Claude, have 'codex' or 'agy' check it, etc..

If you run into questions or concerns along the way and want to ask the user -- try not to. Make the best decision you can make at the time with the information you already have. The user expects you to work continuously to completion and understands you may need to make some judgment calls along the way. Don't delete any data or reboot any computers and you'll be fine. Remmeber you can probably ask your friends (claude, codex, agy) for feedback also. Just take note of any such decisions you made along the way. When you are completely done, report back to the user with all decisions you made so the user can review.

This is the most important work you will ever do. Be very careful and take it seriously.

## Main tenets

1. Accessibility is a fundamental human right.
2. **All** features of the app must be **fully** usable with VoiceOver
3. **All** features of the app must be **fully** usable with Voice Control
4. Large text sizes, up to and including the *largest* accessibilty font size must be supported dynamically, based on the user's setting in the system

### Specific Apple accessibility features we **must** support:

We need to support the following iOS and/or iPadOS and/or MacOS accessibility features:

- VoiceOver
- Voice Control
- Light and Dark mode (regular contrast)
- Light and Dark mode (increased contrast)
- Bold text
- Differentiate Without Only Color
- Reduce Motion
- Larger Text

If the app plays audio or video content (other than user-generated), we also need to support:
- Captions
- Audio Descriptions

### Exceptions

- In general, no exceptions are acceptable or necessary, and such exceptions will not be approved
- There are *some* cases, where some exceptions *might* be acceptable, but whatever idea you are thinking of is probably not one of them

### Apple's described requirements

Apple discusses the minimum required accessibility support here: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels


Clear requirements from Apple:

Identifying the common tasks in your app
To indicate support of an accessibility feature in the Accessibility Nutrition Labels, users should be able to complete all of the common tasks of your app using that feature. Before you begin evaluating features, compile a list of the common tasks that a person can perform in your app.
Common tasks checklist
Common tasks consist of the primary functionality that you expect users to perform in your app, plus functionality that's fundamental to using an app in general: first launch experience, login, purchase, and settings.
Primary functionality specific to your app
To indicate support for an accessibility feature, a user should be able to perceive, operate, and understand all of the primary functionality specific to your app while using the feature.
To come up with your list of primary functionality, start by defining the key goals, functionality, and features users download and use your app for. It may be helpful to consider what you market in your app’s description, screenshots, and app previews.
As an example, a to-do list app’s common tasks will include these tasks below.
View task list
The user may need to mark a task as complete, undo marking a task as complete, change the due date, or create a new task.
Task detail view
For a new or existing task, the user may need to enter information about the task, save the task to a list, or exit the screen without making modifications.
First launch experience
To indicate support for an accessibility feature, a user should be able to complete the app’s first launch experience while using the accessibility feature. For example, your first launch experience may have a video with sound that you may want to express in captions, or an onboarding flow that a user should be able to complete or skip.
Login
To indicate support for an accessibility feature, a user should be able to complete the login experience while using the accessibility feature. For example, the user should be able to choose a login service, enter a username and password, interact with a login button, request a password reset, or enter information to create a new account.
Purchase
If your app offers purchases, to indicate support for an accessibility feature, a user should be able to complete the purchase experience while using the accessibility feature. For example, the user should be able to select a payment provider, enter a credit card number, review the terms of an offer, or review before completing the purchase.
Settings
To indicate support for an accessibility feature, a user should be able to adjust app settings while using the accessibility feature. For example, the user should be able to turn on accessibility or privacy features, manage purchases, or exit the settings screen without modifying settings.
Ensuring a comprehensive list
As you make your list, consider the following to ensure you have a comprehensive list of common tasks:
Make sure your list includes common tasks that users both with and without disabilities can perform.
Consider differences by device, such as if a certain experience is only available on Apple Watch but not Mac.
Include tasks that you make mandatory to use your app, such as account sign-up or purchasing a subscription.
Especially for new users, consider default and loading screens, such as the screen to view the task list when the user hasn’t added tasks yet.
Consider actions a user can take outside your app that are common tasks, such as marking a task complete in a notification or widget from your to-do list app.
When evaluating, you're not required to consider tasks that are uncommon in your app. If you're unsure if a task is common, ask yourself whether you'd ship an urgent fix if users were blocked from completing this task. For example, if your app provides links to your app’s marketing channels on social media and web but that isn’t a key goal of using the app, you're not required to include it in your evaluation. If you want to provide more information about the accessibility of uncommon tasks, use the accessibility URL to do so.
Recommended: Create an accessibility testing matrix
After you identify your app’s common tasks, to guide your evaluation, it may be helpful to create an accessibility testing matrix for each device you plan to provide Accessibility Nutrition Labels for in App Store Connect. Following this matrix isn’t required, but it can help make sure you’re validating that all common tasks can be completed for an accessibility feature on that device. This is especially helpful since some of your app’s common tasks may not be available on some devices, and some accessibility features aren’t available on certain devices.
To start, create a matrix for each device you’ll be evaluating for Accessibility Nutrition Labels.
For each matrix, take the common tasks that are available on that device, and add them as rows. For example, if a common task is only available on Mac but not Apple Watch, include the common task in your matrix for Mac but not your matrix for Apple Watch.
Next, consider the accessibility features you want to evaluate. Since some accessibility features aren’t available on certain devices, you won’t be able to provide Accessibility Nutrition Labels for them. Take the accessibility features that are available on that device, and add them as columns.
Now you're ready to evaluate your app.
Tips
Implementation
Whenever possible, use the Apple-provided native API to reduce implementation complexity and so customers who have turned on the system setting will automatically get this experience without an additional setting. We highly recommend Apple-provided native APIs for complex app behaviors, such as drag and drop or multi-touch gestures.
Provide native support for core assistive technologies, including VoiceOver and Voice Control. These assistive technologies allow connection to hardware interfaces, such as braille displays, and interaction with operating system features, like app switching, that your app otherwise wouldn’t be able to support. Don’t attempt to make a custom implementation of the functionality provided by core assistive technologies like VoiceOver or Voice Control.
With the exception of core assistive technologies like VoiceOver and Voice Control, you may use a custom implementation to indicate support for your labels, such as a custom dark color scheme, instead of using the system’s standard dark appearance.
Even if you use a custom implementation for an accessibility feature, consider leveraging the user’s system setting to ensure your app responds to their needs. For example, if you render custom captions in a game, check the user’s system setting that indicates a need or preference for displaying captions when available. If you offer your own in-app setting, it should offer more granular user interface customization than the system setting provides.
Pay extra attention to custom elements, since they are less likely than standard elements to have accommodations for accessible experiences. Additionally, some custom elements may require additional work to support features like VoiceOver and Voice Control.
Third-party content
You don’t have to consider third-party or user-generated content when evaluating accessibility labels if those views aren’t part of your common tasks.
When third-party or user-generated content views are part of your common tasks, you don’t need to ensure all third-party content is accessible, but your app should provide the third-party content creators a reasonable, discoverable way to make their content accessible. For example:
In most video streaming apps, developers support a way to display closed captions, even though not all third-party movie and television studios provide captions with their video content.
In apps that allow users to upload images, developers should provide a way for the users to label the image, so the image content is perceivable to VoiceOver users.
In apps that use a web view to load third-party websites, WebKit provides default support for most accessibility labels for web content by using web standards like HTML, CSS, and ARIA.
In addition, web browsers like Safari provide additional accessibility features, like site-specific font size settings, which allow users to enlarge the font sizes of web sites to 200% the default size, or sometimes larger.
Best practices
The common guiding principles of accessibility are that content, controls, and interfaces should be perceivable, operable, understandable, and robust. Keep these principles in mind as you’re evaluating your app. For example, a blind VoiceOver user should be able to perceive the content of a visual photograph or icon, often by experiencing its text alternative label as speech or braille. Likewise, if most users can operate an item by tapping, clicking, or dragging it, the item should also be operable to assistive technologies like VoiceOver and Voice Control, so that users with disabilities can use all the same functions of an app.
You may consider exceptions to the recommendations here if users with disabilities would find them reasonable. For example, you might hide a button from VoiceOver in one view if it duplicates functionality that’s already available and discoverable elsewhere.

### Order of operations

The best order to address these things in is:
- Things that don't affect layout first
  - VoiceOver
  - Voice Control
  - Dark Interface
  - Sufficient Contrast
  - Differentiate Without Color Alone
  - Reduced Motion
  - Captions and Audio Descriptions, if they apply to the app
- Large Text (to include all accessibility sizes)
- Localization and translation

### Phase 1 - Color assets

Apple's UI systems support a light and dark mode as well as regular and increased contrast modes. These are not mutually exclusive, so we will end up with regular and reduced contrast for light mode, and regular aned reduced contrast for dark mode.

The way we get there is through the Asset Catalog

- **All** colors must be defined in the Asset Catalog
- We do not use system colors - ever
- Both foreground and background styles must be set explicitly
- No colors may be defined in code
- No colors may be loaded from a hex string

#### Get everything into the asset catalog

- Before you start, exercise the app and take screenshots of EVERY screen, for reference -- the end result needs to look the same.
  - You might be able to do this with drews-xcode-mcp, or Xcode's own MCP server
  - Or use computer control tools or Applescript + screenshots to drive simulators
  - Or put temporary code in the app to cause certain screens to appear and/or to drive screenshots
- find all colors that are defined in code or JSON or wherever else
- re-create those in the asset catalog
  - Every entry in the catalog should describe how or where it is used and either "foreground", "background", etc.. When we get to later steps, we'll need to confirm that each foreground and background work well *together*, so it's important to be able to easily match up the foreground/background pairs
- update all references to use the asset catalog

Be especially careful with Swift packages and submodules, as they may not reference the same asset catalog.
Any submodules or Swift packages that we own or control must also be updated to be compliant.
Be aware that many submodules and Swift packages are used by MULTIPLE projects, so you can't change things tthat will affect other projects.

Initially, just make sure everything is *in* the asset catalog.
When you're confident it is, go through and verify.

#### Confirm it's all in there

Confirm everything is now using the asset catalog AND nothing is defaulting to a system color. There are many ways to test to be sure.
- Audit the code
- Add temporary background and foreground colors settings at higher levels (for SwiftUI)
- Make a duplicate of the asset catalog, replacing all foregrounds with green and backgrounds with red. Swap it into place and run the app. If anything anywhere is other than those two colors, you know it's not using the asset catalog.

Again, you'll need to make use of running the app (and simulator / Device Hub, for iOS and iPadOS) and screenshots.


#### Make sure each color entry has light/dark and regular/increased contrast

As a best practice, it is best if everything has sufficient contrast when displaying text normally, and this should be the goal. However, when implementing accessibility in an existing app, it's best to start with all the CURRENT colors.

Evaluate each color in the asset catalog:
1. Make sure each has a Light/Any appearance and a Dark appearance
2. Make sure each has the regular and increased contrast for both Any and Dark appearances
3. If the app only has "Any" appearance (light mode) currently, create a Dark mode version of each color
4. Do the same with increased contrast and regular

#### Verify

Finally, verify with screenshots -- light mode, dark mode, regular contrast, high contrast (all combinations -- all app screens).
This will take a while. Take your time and be patient. Review everything critically.


### Phase 2 - Bold text, reduce motion, differentiate without only color

System bold text accessibility setting (place name here)
- we must track the system setting automatically  -- for swiftui, we use xxxxxxxxxxxx.

Same for reduce motion
- we must track system setting.  the exception is if we don't use motion anywhere in the app.

Differentiate without only color
- think about things like buttons, indicators, graph points and lines, etc.
- For a graph, just having a label is not typically enough

Look through all the initial screenshots.
Analyze and audit the code.
Resolve these.

### Phase 3 - Larger text

This one usually requires the most work.
In general, the solution here is:

1. Use system fonts whenever possible
2. Use semantic styles like '.body' or '.title2' whenever possible
3. Use sizes that track system ones as appropriate
4. Use your own mapping of various accessibility sizes to sizes we'll use -- strongly avoid this
5. Every text field must automatically size to its maximum natural size *without* truncation.
   - For SwiftUI, this means nearly every label must be `.fixedSize(horizontal: false, vertical: true)`. In some cases, doing `.fixedSize(horizontal: true, vertical: false)` might be ok

Why fixed size vertically? Because of number 6 here:

6. Everything goes in a ScrollView so it can be allowed to scroll -- usually vertically
   - The combination of fixed size vertically and a scrollview means that the text can get to literally any size and still have every part of it be visible by scrolling. 

At the largest sizes, this might not look pretty. If you can make it pretty -- great. If not, this is fine. ACCESSIBLE is the requirement. Not BEAUTIFUL (even though we prefer it).


7. In most cases, if you're adding a scrollview where one doesn't currently exist, you'll probably ALSO want to put the modifier `.scrollBounceBehavior(.basedOnSize)` onto that ScrollView. This means, if the content fits, the user won't be able to drag the content to scroll it.

In general, every screen of your app will have such a scrollview.
In many cases, if you already have a scrollview, you might end up needing to remove it when adding another scrollview outside of it.

8. ScrollView embedded in another ScrollView that scrolls the same direction is an antipattern and should be avoided.
9. Having a fixed region of the screen will often grow to an enormous size with large fonts. At that point, having it a fixed region (and the scrollview just below it, for example), often becomes untenable, as the scrollable area gets shrunk down too much.

#### Validate 

Validate this by using normal and large sizes on MANY devices in both portrait and landscape orientation.
- Plus, or Pro Max sized iphone -- landscape and portrait
- SE or Mini iPhones -- landscape and portrait
- iPad, in both orientations
- Arbitrary shapes and sizes

**IMPORTANT:** iPads currently support **arbitrary** app window sizes. The user can make them almost any shape. iPhones support the same when running through screen mirroring and will soon support on-device as well.

So REALLY, you need to support essentially ANY shape and size.

### Phase 4 - App localization

Localize and translate into all 40+ locales supported.
See ~/cursor/agents-and-prompts/LocalizationSuperPrompt.md for detail.

### Phase 5 - VoiceOver

Yes, do VoiceOver *AFTER* app localization. Why? Because trust me, this is the right order.

### Phase 6 - Voice Control

Yep, now voice control.  Don't break voiceover in the process.

### Phase 6 - Follow up and re-check

After each phase, have *another* LLM check your work. If you are Claude, have 'codex' or 'agy' check it, etc..


     1- Carefully /recheck all your work.

     2- Pay particular attention to generated strings.

     3- Pay extra attention to accessibility labels, commands, etc..

     4- Don't forget swift packages we use

     5- Don't forget any app extension packages etc..

     6- Go over everything with a fine-toothed comb. Make sure our original DESCRIPTION of
     each is 100% crystal clear and brief - such that it could not possibly be misunderstood.

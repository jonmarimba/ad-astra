# Coding in general
- BUILD warnings and RUNTIME warnings are IMPORTANT. Don't ignore them.
- NO silent defaults
- NO unhandled errors
- ALWAYS _one_ source of truth

## Side channels and sidecars
- DO NOT make sidecars or side channels. Don't plumb something new through some oddball path and make a special-case 1-off
   - Ask yourself, "Where SHOULD this go?" 
   - Think about ""What type of thing is this really?" and "Which of our existing concepts and abstractions should be extended to support this new thing?"

## Fallbacks
Fallbacks are another word for silent defaults, and we usually don't want them.
- In most cases, we want the error - to be handled or surfaced as appropriate and feasible.
- If the fallback would only get exercised as a result of a code bug, we don't want it -- we want the error
- If the fallback is to protect against an API call failing, we probably don't want a fallback for that failure either. The exception is a situation where it would make sense to show cached data anyway.

## Multiple Interacting Booleans
When you've got multiple interacting Boolean values, THINK: Is this a place you should be using an enum instead?

## Optional Booleans
An optional boolean is a 3-state variable. What does the nil/null state signify? "No data" or "No option selected yet" or something along those lines should be your answer. If it's another reason, think about if this is the right abstraction.

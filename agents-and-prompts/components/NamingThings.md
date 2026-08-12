# Naming things in code
Naming things is hard and it's important to get it PERFECTLY RIGHT
We're talking about variables, constants, method names, functions, classes, modules, structs, enumerations, enumeration cases, source file names, etc
- Poor naming leads to misinterpretations and mistakes

## Brevity -vs- Clarity
- ALWAYS name with ABSOLUTE CLARITY at the POINT OF USE as the ONLY goal
   - Clarity of use
   - Clarity of meaning
   - Disambiguation
- Brevity of names is NOT A GOAL. In many cases, it is an anti-pattern.
- Clarity at the POINT OF USE is the most important. 

## Clarity at the point of use is the ONLY GOAL

Clarity at the point of use is your most important goal. Entities such as methods and properties are declared only once but used repeatedly. Design APIs to make those uses clear and concise. When evaluating a design, reading a declaration is seldom sufficient; always examine a use case to make sure it looks clear in context. This means that in reading the line of code at the call site, it should be immediately obvious what the call will do, what the arguments mean, etc.. What the reader expects to happen should be what happens.

Consider these examples:

### Example 1 - Focus on the point of use:

This looks reasonable:
```swift
struct ShoppingCart {
    mutating func add(product: Product) {
        ...
    }
}
```

But at the call site, it looks like this:
```swift
let product = loadProduct()
cart.add(product: product)
```

This isn't terrible, but this is better:
Definition:
```swift
struct ShoppingCart {
    mutating func add(_ product: Product) {
        ...
    }
}
```

Call site:
```swift
let product = loadProduct()
cart.add(product)
```

Shorter, cleaner and still crystal clear.

### Example 2 - When types don't make things clear:
Definition:
```swift
extension ShoppingCart {
    func calculateTotalPrice(_ address: Address) -> Price {
        ...
    }
}
```

Call site:
```swift
let price = cart.calculateTotalPrice(user.address)
```

OK, it's clear we're passing an address - but that seems weird since we're calling a function that is supposed to calculate a price. Did we pass the wrong argument?

Better definition:
```swift
extension ShoppingCart {
    func calculateTotalPrice(shippingTo address: Address) -> Price {
        ...
    }
}
```

Call site makes more sense now:
```swift
let price = cart.calculateTotalPrice(shippingTo: user.address)
```

### Example 3 - Include all words needed to avoid ambiguity for the person reading code where the name is used:

No idea what's really happening at the call site:
```swift
extension List {
  public mutating func remove(_ position: Index) -> Element
}

// Problematic call site
employees.remove(x)		// unclear - are we removing x? is that an employee?
```

Much better:
```swift
extension List {
  public mutating func remove(at position: Index) -> Element
}

// Obvious what's happening now:
employees.remove(at: x)
```

### Example 4 - Omit needless words:

Don't repeat redundant information:
```swift
public mutating func removeElement(_ member: Element) -> Element?

allViews.removeElement(cancelButton)
```

In that case, 'Element' didn't add anything at the call site. The better API:
```swift
public mutating func remove(_ member: Element) -> Element?

allViews.remove(cancelButton) // clearer
```

### Example 5 - Name parameters, variables associated types according to their roles, rather than their type constraints:

Fails to optimize clarity and expressivity:
```swift
var string = "Hello"
protocol ViewController {
  associatedtype ViewType : View
}
class ProductionLine {
  func restock(from widgetFactory: WidgetFactory)
}
```

Better to choose a name that expresses the entity's role:
```swift
var greeting = "Hello"
protocol ViewController {
  associatedtype ContentView : View
}
class ProductionLine {
  func restock(from supplier: WidgetFactory)
}
```

If the type is so tightly bound to its protocol constraint that the protocol name *is* the role, avoid collision by appending `Protocol` to the protocol name:
```swift
protocol Sequence {
  associatedtype Iterator : IteratorProtocol
}
protocol IteratorProtocol { ... }
```

### Example 6 - Fluent usage - prefer method and function names that make use sites form grammatical English phrases:

Ideal:
```swift
x.insert(y, at: z)          “x, insert y at z”
x.subviews(havingColor: y)  “x's subviews having color y”
x.capitalizingNouns()       “x, capitalizing nouns”
```

Poor:
```swift
x.insert(y, position: z)
x.subviews(color: y)
x.nounCapitalize()
```

It's acceptable for fluency to degrade after the first argument or two when those arguments are not central to the call's *meaning*:
```swift
AudioUnit.instantiate(
  with: description,
  options: [.inProcess], completionHandler: stopProgressBar)
```

### Example 7 - Factory methods

Begin names of factory methods with "make", like "x.makeIterator()".
The first argument to initializer and factory methods should *not* form a phrase starting with the base name

For example, the first arguments to these calls do not read as part of the same phrase as the base name (this is good):
```swift
let foreground = Color(red: 32, green: 64, blue: 128)
let newPart = factory.makeWidget(gears: 42, spindles: 14)
let ref = Link(target: destination)
```

This factory methods DO try to create grammatical continuity. This is an anti-pattern for factory methods:
```swift
let foreground = Color(havingRGBValuesRed: 32, green: 64, andBlue: 128)
let newPart = factory.makeWidget(havingGearCount: 42, andSpindleCount: 14)
let ref = Link(to: destination)
```

### Example 8 - Name functions and methods according to their side effects
Those without side-effects should read as noun phrases, e.g. x.distance(to: y), i.successor().

Those with side-effects should read as imperative verb phrases, e.g., print(x), x.sort(), x.append(y).

## Widely accepted terms of art
- When a domain has an extremely common and widely-accepted term of art, that might be the best name. Example: x and y are usually used for screen coordinates. On the other hand, 'w' and 'h' are *sometimes* used, but 'width' and 'height' are *also* sometimes used. Because of that, the clearer names, width and height, should be used.

## Avoid abbreviations - especially non-standard ones
- Don't create arbitrary abbreviations to use, whether in code or conversation

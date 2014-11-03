### Selectors with custom combinators 
inspired by Slick of mootools fame (shout-out & credits)

Combinators fetch new elements, while qualifiers filter them.

###

Command = require('../concepts/Command')
Query   = require('./Query')

class Selector extends Query
  type: 'Selector'
  
  constructor: (operation) ->
    @key = @path = @serialize(operation)


  prepare: (operation, parent) ->
    prefix = ((parent && operation.name != ' ') || 
          (operation[0] != '$combinator' && typeof operation[1] != 'object')) && 
          ' ' || ''
    switch operation[0]
      when '$tag'
        if (!parent || operation == operation.selector?.tail) && operation[1][0] != '$combinator'
          tags = ' '
          index = (operation[2] || operation[1]).toUpperCase()
      when '$combinator'
        tags = prefix + operation.name
        index = operation.parent.name == "$tag" && operation.parent[2].toUpperCase() || "*"
      when '$class', '$pseudo', '$attribute', '$id'
        tags = prefix + operation[0]
        index = (operation[2] || operation[1])
    return unless tags
    ((@[tags] ||= {})[index] ||= []).push operation

    
  # String to be used to join tokens in a list
  separator: ''
  # Does selector start with ::this?
  scoped: undefined

  # Redefined function name for serialized key
  prefix: undefined
  # Trailing string for a serialized key
  suffix: undefined

  # String representation of current selector operation
  key: undefined
  # String representation of current selector operation chain
  path: undefined

  # Reference to first operation in tags
  tail: undefined
  # Reference to last operation in tags
  head: undefined

  # Does the selector return only one element?
  singular: undefined
  # Is it a "free" selector like ::this or ::scope?
  hidden: undefined
  
  
  relative: undefined

      
    
  # Check if query was already updated
  before: (args, engine, operation, continuation, scope) ->
    unless @hidden
      return engine.queries.fetch(args, operation, continuation, scope)

  # Subscribe elements to query 
  after: (args, result, engine, operation, continuation, scope) ->
    unless @hidden
      return engine.queries.update(args, result, operation, continuation, scope)


Selector::mergers.selector = (command, other, parent, operation, inherited) ->
  if !other.head
    # Native selectors cant start with combinator other than whitespace
    if other instanceof Selector.Combinator && operation[0] != ' '
      return

  # Can't append combinator to qualifying selector selector 
  if selecting = command instanceof Selector.Selecter
    return unless other.selecting
  else if other.selecting
    command.selecting = true

  other.head = parent
  command.head = parent
  command.tail = other.tail || operation
  command.tail.head = parent
  
  left = other.selector || other.key
  right = command.selector || command.key
  command.selector = 
    if inherited
      right + command.separator + left
    else
      left + right
  return true

# Indexed collection
class Selector.Selecter extends Selector
  signature: [
    query: ['String']
  ]

# Scoped indexed collections
class Selector.Combinator extends Selector.Selecter
  signature: [[
    context: ['Selector']
    query: ['String']
  ]]

# Filter elements by key
class Selector.Qualifier extends Selector
  signature: [
    context: ['Selector']
    matcher: ['String']
  ]

# Filter elements by key with value
class Selector.Search extends Selector
  signature: [
    context: ['Selector']
    matcher: ['String']
    query: ['String']
  ]
  
# Reference to related element
class Selector.Element extends Selector
  signature: []
  
Selector.define
  # Live collections

  'class':
    prefix: '.'
    tags: ['selector']
    
    Selecter: (value, engine, operation, continuation, scope) ->
      return scope.getElementsByClassName(value)
      
    Qualifier: (node, value) ->
      return node if node.classList.contains(value)

  'tag':
    tags: ['selector']
    prefix: ''

    Selecter: (value, engine, operation, continuation, scope) ->
      return scope.getElementsByTagName(value)
    
    Qualifier: (node, value) ->
      return node if value == '*' || node.tagName == value.toUpperCase()

  # DOM Lookups

  'id':
    prefix: '#'
    tags: ['selector']
    
    Selecter: (id, engine, operation, continuation, scope = @scope) ->
      return scope.getElementById?(id) || node.querySelector('[id="' + id + '"]')
      
    Qualifier: (node, value) ->
      return node if node.id == value


  # All descendant elements
  ' ':
    tags: ['selector']
    
    Combinator: (node) ->
      return node.getElementsByTagName("*")

  # All parent elements
  '!':
    Combinator: (node) ->
      nodes = undefined
      while node = node.parentNode
        if node.nodeType == 1
          (nodes ||= []).push(node)
      return nodes

  # All children elements
  '>':
    tags: ['selector']

    Combinator: (node) -> 
      return node.children

  # Parent element
  '!>':
    Combinator: (node) ->
      return node.parentElement

  # Next element
  '+':
    tags: ['selector']
    Combinator: (node) ->
      return node.nextElementSibling

  # Previous element
  '!+':
    Combinator: (node) ->
      return node.previousElementSibling

  # All direct sibling elements
  '++':
    Combinator: (node) ->
      nodes = undefined
      if prev = node.previousElementSibling
        (nodes ||= []).push(prev)
      if next = node.nextElementSibling
        (nodes ||= []).push(next)
      return nodes

  # All succeeding sibling elements
  '~':
    tags: ['selector']

    Combinator: (node) ->
      nodes = undefined
      while node = node.nextElementSibling
        (nodes ||= []).push(node)
      return nodes

  # All preceeding sibling elements
  '!~':
    Combinator: (node) ->
      nodes = undefined
      prev = node.parentNode.firstElementChild
      while prev != node
        (nodes ||= []).push(prev)
        prev = prev.nextElementSibling
      return nodes

  # All sibling elements
  '~~':
    Combinator: (node) ->
      nodes = undefined
      prev = node.parentNode.firstElementChild
      while prev
        if prev != node
          (nodes ||= []).push(prev) 
        prev = prev.nextElementSibling
      return nodes


Selector.define
  # Pseudo elements
  '::this':
    hidden: true
    log: ->

    Element: (engine, operation, continuation, scope) ->
      return scope

    continue: (engine, operation, continuation) ->
      return continuation


  # Parent element (alias for !> *)
  '::parent':
    Element: Selector['!>']::Combinator

  # Current engine scope (defaults to document)
  '::root':
    Element: (engine, operation, continuation, scope) ->
      return engine.scope

  # Return abstract reference to window
  '::window':
    hidden: true
    Element: ->
      return '::window' 
  

Selector.define  
  '[=]':
    tags: ['selector']
    prefix: '['
    separator: '="'
    suffix: '"]'
    Search: (node, attribute, value) ->
      return node if node.getAttribute(attribute) == value

  '[*=]':
    tags: ['selector']
    prefix: '['
    separator: '*="'
    suffix: '"]'
    Search: (node, attribute, value) ->
      return node if node.getAttribute(attribute)?.indexOf(value) > -1

  '[|=]':
    tags: ['selector']
    prefix: '['
    separator: '|="'
    suffix: '"]'
    Search: (node, attribute, value) ->
      return node if node.getAttribute(attribute)?

  '[]':
    tags: ['selector']
    prefix: '['
    suffix: ']'
    Search: (node, attribute) ->
      return node if node.getAttribute(attribute)?



# Pseudo classes

Selector.define
  ':value':
    Qualifier: (node) ->
      return node.value
    watch: "oninput"

  ':get':
    Combinator: (property, engine, operation, continuation, scope) ->
      return scope[property]

  ':first-child':
    tags: ['selector']
    Combinator: (node) ->
      return node unless node.previousElementSibling

  ':last-child':
    tags: ['selector']
    Combinator: (node) ->
      return node unless node.nextElementSibling


  ':next':
    relative: true
    Combinator: (node, engine, operation, continuation, scope) ->
      collection = engine.queries.getScopedCollection(operation, continuation, scope)
      index = collection?.indexOf(node)
      return if !index? || index == -1 || index == collection.length - 1
      return collection[index + 1]

  ':previous':
    relative: true
    Combinator: (node, engine, operation, continuation, scope) ->
      collection = engine.queries.getScopedCollection(operation, continuation, scope)
      index = collection?.indexOf(node)
      return if index == -1 || !index
      return collection[index - 1]

  ':last':
    relative: true
    singular: true
    Combinator: (node, engine, operation, continuation, scope) ->
      collection = engine.queries.getScopedCollection(operation, continuation, scope)
      index = collection?.indexOf(node)
      return if !index?
      return node if index == collection.length - 1

  ':first':
    relative: true
    singular: true
    Qualifier: (node, engine, operation, continuation, scope) ->
      collection = engine.queries.getScopedCollection(operation, continuation, scope)
      index = collection?.indexOf(node)
      return if !index?
      return node if index == 0
  
  # Comma combines results of multiple selectors without duplicates
  ',':
    # If all sub-selectors are selector, make a single comma separated selector
    tags: ['selector']

    # Dont let undefined arguments stop execution
    eager: true

    # Match all kinds of arguments
    signature: null,


    separator: ','

    # Comma only serializes arguments
    serialize: ->
      return ''

    # Return deduplicated collection of all found elements
    command: (engine, operation, continuation, scope) ->
      contd = @Continuation.getScopePath(scope, continuation) + operation.path
      if @queries.ascending
        index = @engine.indexOfTriplet(@queries.ascending, operation, contd, scope) == -1
        if index > -1
          @queries.ascending.splice(index, 3)

      return @queries[contd]

    # Recieve a single element found by one of sub-selectors
    # Duplicates are stored separately, they dont trigger callbacks
    yield: (result, engine, operation, continuation, scope, ascender) ->
      contd = engine.Continuation.getScopePath(scope, continuation) + operation.parent.path
      engine.queries.add(result, contd, operation.parent, scope, operation, continuation)
      engine.queries.ascending ||= []
      if engine.indexOfTriplet(engine.queries.ascending, operation.parent, contd, scope) == -1
        engine.queries.ascending.push(operation.parent, contd, scope)
      return true

    # Remove a single element that was found by sub-selector
    # Doesnt trigger callbacks if it was also found by other selector
    release: (result, engine, operation, continuation, scope) ->
      contd = engine.Continuation.getScopePath(scope, continuation) + operation.parent.path
      engine.queries.remove(result, contd, operation.parent, scope, operation, undefined, continuation)
      return true

if document?
  # Add shims for IE<=8 that dont support some DOM properties
  dummy = Selector.dummy = document.createElement('_')

  unless dummy.hasOwnProperty("classList")
    Selector['class']::Qualifier = (node, value) ->
      return node if node.className.split(/\s+/).indexOf(value) > -1
      
  unless dummy.hasOwnProperty("parentElement") 
    Selector['!>']::Combinator = Selector['::parent']::Element = (node) ->
      if parent = node.parentNode
        return parent if parent.nodeType == 1
  unless dummy.hasOwnProperty("nextElementSibling")
    Selector['+']::Combinator = (node) ->
      while node = node.nextSibling
        return node if node.nodeType == 1
    Selector['!+']::Combinator = (node) ->
      while node = node.previousSibling
        return node if node.nodeType == 1
    Selector['++']::Combinator = (node) ->
      nodes = undefined
      prev = next = node
      while prev = prev.previousSibling
        if prev.nodeType == 1
          (nodes ||= []).push(prev)
          break
      while next = next.nextSibling
        if next.nodeType == 1
          (nodes ||= []).push(next)
          break
      return nodes
    Selector['~']::Combinator = (node) ->
      nodes = undefined
      while node = node.nextSibling
        (nodes ||= []).push(node) if node.nodeType == 1
      return nodes
    Selector['!~']::Combinator = (node) ->
      nodes = undefined
      prev = node.parentNode.firstChild
      while prev && (prev != node)
        (nodes ||= []).push(prev) if prev.nodeType == 1
        prev = prev.nextSibling
      return nodes
    Selector['~~']::Combinator = (node) ->
      nodes = undefined
      prev = node.parentNode.firstChild
      while prev
        if prev != node && prev.nodeType == 1
          (nodes ||= []).push(prev) 
        prev = prev.nextSibling
      return nodes
    Selector[':first-child']::Qualifier = (node) ->
      if parent = node.parentNode
        child = parent.firstChild
        while child && child.nodeType != 1
          child = child.nextSibling
        return node if child == node
    Selector[':last-child']::Qualifier = (node) ->
      if parent = node.parentNode
        child = parent.lastChild
        while child && child.nodeType != 1
          child = child.previousSibling
        return mpde if child == node

module.exports = Selector
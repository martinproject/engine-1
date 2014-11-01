### 

Generate lookup structures to match methods by name and argument type signature

Signature for `['==', ['get', 'a'], 10]` would be `engine.signatures['==']['Value']['Number']`

A matched signature returns customized class for an operation that can further 
pick a sub-class dynamically. Signatures allows special case optimizations and 
composition to be implemented structurally, instead of branching in runtime.

Signatures are shared between commands. Dispatcher support css-style 
typed optional argument groups, but has no support for keywords or repeating groups yet
###
Command = require('../concepts/Command')

class Signatures
  
  constructor: (@engine) ->
    
  # Register signatures defined in a given object
  sign: (command, object) ->
    if signed = command.__super__.signed
      return signed
    command.__super__.signed = storage = []
    if signature = object.signature
      @get command, storage, signature
    else if signatures = object.signatures
      for signature in signatures
        @get command, storage, signature
    else
      storage.push ['default']
    return storage
        
  # Reorder keys within optional group
  permute: (arg, permutation) ->
    keys = Object.keys(arg)
    return keys unless permutation
    values = Object.keys(arg)
    group = []
    
    # Put keys at their permuted places
    for position, index in permutation
      unless position == null
        group[position] = keys[index]
    
    # Fill blank spots with     
    for i in [permutation.length ... keys.length] by 1
      for j in [0 ... keys.length] by 1
        unless group[j]?
          group[j] = keys[i]
          break
          
    # Validate that there're no holes
    for arg in group
      if arg == undefined
        return
        
    return group

  # Return array of key names for current permutation
  getPermutation: (args, properties) ->
    result = []
    for arg, index in args
      unless arg == null
        result[arg] = properties[index]
    for arg, index in result by -1
      unless arg?
        result.splice(index, 1)
    return result

  # Return array with positions for given argument signature
  getPositions: (args) ->
    result = []
    for value, index in args
      if value?
        result[value] = index
    for arg, index in result by -1
      unless arg?
        result.splice(index, 1)
    return result

  # Return array of keys for a full list of arguments
  getProperties: (signature) ->
    if properties = signature.properties
      return properties
    signature.properties = properties = []
    for arg in signature
      if arg.push
        for a in arg
          for property, definition of a
            properties.push(definition)
      else
        for property, definition of arg
          properties.push(definition)
    return properties

  # Generate a list of all type paths
  generate: (combinations, positions, properties, combination) ->
    if combination
      i = combination.length
    else
      combination = []
      combinations.push(combination)
      i = 0

    while (props = properties[i]) == undefined && i < properties.length
      i++

    if i == properties.length
      combination.push positions
    else
      for type, j in properties[i]
        if j == 0
          combination.push(type)
        else
          position = combinations.indexOf(combination)
          combination = combination.slice(0, i)
          combination.push type
          combinations.push(combination)
        @generate combinations, positions, properties, combination
    return combinations
  # Create actual nested lookup tables for argument types
  
  write: (command, storage, combination)->
    for i in [0 ... combination.length]
      if (arg = combination[i]) == 'default'
        storage.Default = command
      else
        if i < combination.length - 1
          storage = storage[arg] ||= {}
        else
          storage.resolved ||= Command.extend.call(command, permutation: arg)
    return

  # Write cached lookup tables into a given storage (register method by signature)
  set: (property, command, types) ->
    storage = @[property] ||= {}

    for type of types

      if execute = command.prototype?[type]
        subcommand = command[type] ||= types[type].extend(command.prototype)
        subcommand::execute = execute
        for combination in @sign(subcommand, subcommand.prototype)
          @write subcommand, storage, combination

    for combination in @sign(command, command.prototype)
      @write command, storage, combination

    return
    
  # Generate a lookup structure to find method definition by argument signature
  get: (command, storage, signature, args, permutation) ->

    args ||= []
    i = args.length
    
    # Find argument by index in definition
    `seeker: {`
    for arg in signature
      if arg.push
        for obj, k in arg
          j = 0
          group = arg
          for property of obj
            unless i
              arg = obj
              unless keys = @permute(arg,  permutation)
                return
              argument = arg[property]
              `break seeker`
            i--
            j++
      else
        j = undefined
        for property of arg
          unless i
            argument = arg[property]
            `break seeker`
          i--
    `}`
    
    # End of signature
    unless argument
      @generate(storage, @getPositions(args), @getPermutation(args, @getProperties(signature)))
      return
      
    # Permute optional argument within its group
    if keys && j?
      permutation ||= []
      
      for i in [0 ... keys.length] by 1
        if permutation.indexOf(i) == -1
          @get command, storage, signature, args.concat(args.length - j + i), permutation.concat(i)
  
      @get command, storage, signature, args.concat(null), permutation.concat(null)
      return
        
    # Register all input types for given arguments
    @get command, storage, signature, args.concat(args.length)

module.exports = Signatures
// we need to be smarter about figuring out where we're at in a JSON file

// it's still pretty crappy to figure out where we are in JSON, currently having
// issues with scopeDescriptor.getScopesArray()[4] == "punctuation.definition.string.end.json"
// which is the last else if

// seems to be breaking on underscores -- EDIT: No, it breaks on numbers

// ALL_BORROWERS_NAMES isn't getting pulled from custom_form.rb

const imageURL = '<image src="' + atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/simplenexus-icon-transparent.png' + '"/>'

module.exports =
class snProvider {
  constructor(placeholderSet) {
    this.selector = '.text.html, .source.json'
    this.inclusionPriority = 1
    this.suggestionPriority = 2
    this.placeholderSet = placeholderSet

    this.snTypeSuggestions = buildSnTypeSet()
    this.snFieldSuggestions = buildSnFieldSet()
  }

  getSuggestions({scopeDescriptor, prefix, editor, bufferPosition}) {
    const suggestions = []

    var sortedPlaceholderArray = Array.from(this.placeholderSet).sort()

    if (!(prefix != null ? prefix.length : undefined)) { return }

    // we need to figure out if we're working with JSON or HTML
    if (scopeDescriptor.getScopesArray().indexOf('text.html.basic') > -1) {
      var newPrefix = getPrefix(editor, bufferPosition, scopeDescriptor)
      if (newPrefix) {
        if (newPrefix.key == 'html') {
          sortedPlaceholderArray.forEach( function(item) {
            if (item.includes(newPrefix.prefix.toUpperCase())) {
              suggestions.push({
                text: item,
                iconHTML: imageURL
              })
            }
          })
        }
      }
    } else if (scopeDescriptor.getScopesArray().indexOf('source.json') > -1) {
      if (scopeDescriptor.getScopesArray()[8] == "punctuation.definition.string.end.json") {
        sortedPlaceholderArray.forEach(function(item) {
          if (item.includes(prefix.toUpperCase())) {
            suggestions.push({
              text: item.toLowerCase(),
              iconHTML: imageURL
            })
          }
        })
      } else if (scopeDescriptor.getScopesArray()[7] == "punctuation.definition.string.end.json") {
        var newPrefix = getPrefix(editor, bufferPosition, scopeDescriptor)
        if (newPrefix) {
          if (newPrefix.key == 'key') {
            sortedPlaceholderArray.forEach(function(item) {
              if (item.includes(newPrefix.prefix.toUpperCase())) {
                suggestions.push({
                  text: item.toLowerCase(),
                  iconHTML: imageURL
                })
              }
            })
          } else if (newPrefix.key == 'type') {
            this.snTypeSuggestions.forEach( function (item) {
              if (item.text.includes(newPrefix.prefix)) {
                suggestions.push(item)
              }
            })
          }
        }
      } else if (scopeDescriptor.getScopesArray()[4] == "punctuation.definition.string.end.json") {
        this.snFieldSuggestions.forEach( function (item) {
          if (item.text.includes(prefix)) {
            suggestions.push(item)
          }
        })
      }
    }

    return suggestions
  }
}

function getPrefix(editor, bufferPosition, scopeDescriptor, prefix) {
  // Get the text for the line up to the triggered buffer position
  var line = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])

  if (scopeDescriptor.getScopesArray().indexOf('text.html.basic') > -1) {
    var nearestBracket = -1

    // Probably a dumb way to do this, but lets look for the nearest '[' to bufferPosition
    for (var i = bufferPosition.column; i >= 0; i--) {
      if (line.charAt(i) == '[') {
        nearestBracket = i
        break
      }
    }

    // If we couldn't find a bracket, let's get the heck out of here
    if (nearestBracket == -1) {
      return prefix
    }

    return {key: 'html', prefix: line.substring(nearestBracket + 1, bufferPosition.column)}
  } else if (scopeDescriptor.getScopesArray().indexOf('source.json') > -1) {
    var semiColon = -1

    for (var i = bufferPosition.column; i >= 0; i--) {
      if (line.charAt(i) == ':') {
        semiColon = i
        break
      }
    }

    if (semiColon == -1) {
      return
    }

    if (line.substring(semiColon - 5, semiColon) == "\"key\"") {
      return {key: 'key', prefix: line.substring(semiColon + 3, bufferPosition.column)}
    }

    if (line.substring(semiColon - 6, semiColon) == "\"type\"") {
      return {key: 'type', prefix: line.substring(semiColon + 3, bufferPosition.column)}
    }

    return
  }
}

function buildSnTypeSet() {
  var snTypeSet = []

  snTypeSet.push({
    text: 'agreement',
    iconHTML: imageURL,
    description: 'Boolean, but user must agree before proceeding'
  })

  snTypeSet.push({
    text: 'boolean',
    iconHTML: imageURL,
    description: 'Yes or No'
  })

  snTypeSet.push({
    text: 'currency',
    iconHTML: imageURL,
    description: 'Number but with currency validation'
  })

  snTypeSet.push({
    text: 'email',
    iconHTML: imageURL,
    description: 'Text but with email validation'
  })

  snTypeSet.push({
    text: 'info',
    iconHTML: imageURL,
    description: 'Displays text without requiring user input'
  })

  snTypeSet.push({
    text: 'integer',
    iconHTML: imageURL,
    description: 'Non-decimal numbers'
  })

  snTypeSet.push({
    text: 'multi_choice',
    iconHTML: imageURL,
    description: 'Checkbox group with choices defined in choices: []'
  })

  snTypeSet.push({
    text: 'phone',
    iconHTML: imageURL,
    description: 'Used for phone numbers'
  })

  snTypeSet.push({
    text: 'percentage',
    iconHTML: imageURL,
    description: 'Number with decimal'
  })

  snTypeSet.push({
    text: 'single_choice',
    iconHTML: imageURL,
    description: 'Dropdown box with choices defined in choices: []'
  })

  snTypeSet.push({
    text: 'ssn',
    iconHTML: imageURL,
    description: 'Integer, but with ssn validation'
  })

  snTypeSet.push({
    text: 'state',
    iconHTML: imageURL,
    description: 'Presents a state dropdown'
  })

  snTypeSet.push({
    text: 'text',
    iconHTML: imageURL,
    description: 'Any valid text'
  })

  snTypeSet.push({
    text: 'zip',
    iconHTML: imageURL,
    description: 'Integer, but with zip validation'
  })

  return snTypeSet
}

function buildSnFieldSet() {
  var snFieldSet = []

  snFieldSet.push({
    text: 'name',
    iconHTML: imageURL,
    description: 'Name of the form you are creating (1003 Short Form, Pre-Qualification Form, Pre-Approval Form)'
  })

  snFieldSet.push({
    text: 'structure',
    iconHTML: imageURL,
    description: 'Contains the layout of the form, consisting of fields and instructions'
  })

  snFieldSet.push({
    text: 'values',
    iconHTML: imageURL,
    description: 'Any values you want to pre-determine'
  })

  snFieldSet.push({
    text: 'fields',
    iconHTML: imageURL,
    description: 'The definitions of the fields you used in structure'
  })

  snFieldSet.push({
    text: 'version',
    iconHTML: imageURL,
    description: 'Should pretty much always be 1.0'
  })

  return snFieldSet
}

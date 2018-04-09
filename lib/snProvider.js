// we need to be smarter about figuring out where we're at in a JSON file

const imageURL = atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/simplenexus-icon-transparent.png'

module.exports =
class snProvider {
  constructor(placeholderSet) {
    this.selector = '.text.html, .source.json'
    this.inclusionPriority = 1
    this.suggestionPriority = 2
    this.placeholderSet = placeholderSet

    this.snTypeSuggestions = buildSnTypeSet()
  }

  getSuggestions({scopeDescriptor, prefix, editor, bufferPosition}) {
    const suggestions = []

    var iterator = this.placeholderSet.values()
    var value

    if (!(prefix != null ? prefix.length : undefined)) { return }

    // we need to figure out if we're working with JSON or HTML
    if (scopeDescriptor.getScopesArray().indexOf('text.html.basic') > -1) {
      var newPrefix = getPrefix(editor, bufferPosition, scopeDescriptor)
      if (newPrefix) {
        if (newPrefix.key == 'html') {
          while (value = iterator.next().value) {
            if (value.startsWith(newPrefix.prefix.toUpperCase())) {
              suggestions.push({
                text: value,
                iconHTML: '<image src="' + imageURL + '"/>'
              })
            }
          }
        }
      }
    } else if (scopeDescriptor.getScopesArray().indexOf('source.json') > -1) {
      if (scopeDescriptor.getScopesArray()[8] == "punctuation.definition.string.end.json") {
        while (value = iterator.next().value) {
          if (value.startsWith(prefix.toUpperCase())) {
            suggestions.push({
              text: value.toLowerCase(),
              iconHTML: '<image src="' + imageURL + '"/>'
            })
          }
        }
      } else if (scopeDescriptor.getScopesArray()[7] == "punctuation.definition.string.end.json") {
        var newPrefix = getPrefix(editor, bufferPosition, scopeDescriptor)
        if (newPrefix) {
          if (newPrefix.key == 'key') {
            while (value = iterator.next().value) {
              if (value.startsWith(newPrefix.prefix.toUpperCase())) {
                suggestions.push({
                  text: value.toLowerCase(),
                  iconHTML: '<image src="' + imageURL + '"/>'
                })
              }
            }
          } else if (newPrefix.key == 'type') {
            // console.log("suggestions array")
            // console.log(this.snTypeSuggestions)
            // yourArray.forEach( function (arrayItem)
            // {
            //     var x = arrayItem.prop1 + 2;
            //     alerelrt(x);
            // });
            this.snTypeSuggestions.forEach( function (item) {
              if (item.text.startsWith(newPrefix.prefix)) {
                suggestions.push(item)
              }
            })
            // for (var item in this.snTypeSuggestions) {
            //   console.log("current suggestions")
            //   console.log(item)
            //   if (item.text.startsWith(newPrefix.prefix)) {
            //     suggestions.push(item)
            //   }
            // }
            // console.log("FAFFAFFA")
            // console.log(newPrefix.prefix)
          }
        }
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
    iconHTML: '<image src="' + imageURL + '"/>',
    description: 'I don\'t know why this is different than boolean'
  })

  snTypeSet.push({
    text: 'boolean',
    iconHTML: '<image src="' + imageURL + '"/>',
    description: 'Yes or No'
  })

  snTypeSet.push({
    text: 'currency',
    iconHTML: '<image src="' + imageURL + '"/>',
    description: 'Number but with currency validation'
  })

  snTypeSet.push({
    text: 'email',
    iconHTML: '<image src="' + imageURL + '"/>',
    description: 'Text but with email validation'
  })

  snTypeSet.push({
    text: 'integer',
    iconHTML: '<image src="' + imageURL + '"/>',
    description: 'Non-decimal numbers'
  })

  snTypeSet.push({
    text: 'multi_choice',
    iconHTML: '<image src="' + imageURL + '"/>',
    description: 'Checkbox group with choices defined in choices: []'
  })

  snTypeSet.push({
    text: 'phone',
    iconHTML: '<image src="' + imageURL + '"/>',
    description: 'Used for phone numbers'
  })

  snTypeSet.push({
    text: 'percentage',
    iconHTML: '<image src="' + imageURL + '"/>',
    description: 'Similar to something, I think'
  })

  snTypeSet.push({
    text: 'single_choice',
    iconHTML: '<image src="' + imageURL + '"/>',
    description: 'Dropdown box with choices defined in choices: []'
  })

  snTypeSet.push({
    text: 'ssn',
    iconHTML: '<image src="' + imageURL + '"/>',
    description: 'Integer, but with ssn validation'
  })

  snTypeSet.push({
    text: 'state',
    iconHTML: '<image src="' + imageURL + '"/>',
    description: 'Presents a state dropdown'
  })

  snTypeSet.push({
    text: 'text',
    // snippet: 'someText(${1:myArg})'
    // displayText: 'someText' # (optional)
    // replacementPrefix: 'so' # (optional)
    // type: 'function' # (optional)
    // leftLabel: '' # (optional)
    // leftLabelHTML: '' # (optional)
    // rightLabel: '' # (optional)
    // rightLabelHTML: '' # (optional)
    // className: '' # (optional)
    iconHTML: '<image src="' + imageURL + '"/>',
    description: 'Any valid text'
    // descriptionMoreURL: '' # (optional)
    // characterMatchIndices: [0, 1, 2] # (optional)
  })

  snTypeSet.push({
    text: 'zip',
    iconHTML: '<image src="' + imageURL + '"/>',
    description: 'Similar to integer, but with zip validation'
  })

  return snTypeSet
}

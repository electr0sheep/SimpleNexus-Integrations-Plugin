// we need to be smarter about figuring out where we're at in a JSON file

// it's still pretty crappy to figure out where we are in JSON, currently having
// issues with scopeDescriptor.getScopesArray()[4] == "punctuation.definition.string.end.json"
// which is the last else if

// seems to be breaking on underscores -- EDIT: No, it breaks on numbers

// the types don't seem to enter when you hit enter on them

const snLogoImageURL = '<image src="' + atom.packages.getPackageDirPaths()[0] + '/SimpleNexus-Integrations-Plugin/simplenexus/images/simplenexus-icon-transparent.png' + '"/>'
const lqbLogoImageURL = '<image src="' + atom.packages.getPackageDirPaths()[0] + '/SimpleNexus-Integrations-Plugin/simplenexus/images/lqb.png' + '"/>'
const encompassLogoImageURL ='<image src="' + atom.packages.getPackageDirPaths()[0] + '/SimpleNexus-Integrations-Plugin/simplenexus/images/encompass.png' + '"/>'
const encomplqbLogoImageURL = '<image src="' + atom.packages.getPackageDirPaths()[0] + '/SimpleNexus-Integrations-Plugin/simplenexus/images/lqb-encompass.png' + '"/>'
const nmmLogoImageURL = '<image src="' + atom.packages.getPackageDirPaths()[0] + '/SimpleNexus-Integrations-Plugin/simplenexus/images/nmm.png' + '"/>'

var placeholderJSON

module.exports =
class snProvider {
  constructor(pJSON) {
    placeholderJSON = pJSON
    this.selector = '.text.html, .source.json'
    this.inclusionPriority = 1
    this.suggestionPriority = 3
    this.placeholderSet = []

    for (var key in placeholderJSON) {
      this.placeholderSet.push(key)
    }

    this.placeholderSet.sort()

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
                iconHTML: getImageURL(item)
              })
            }
          })
        }
      }
    } else if (scopeDescriptor.getScopesArray().indexOf('source.json') > -1) {
      // structure
      if (scopeDescriptor.getScopesArray()[8] == "punctuation.definition.string.end.json" || scopeDescriptor.getScopesArray()[9] == "punctuation.definition.string.end.json") {
        sortedPlaceholderArray.forEach(function(item) {
          if (item.includes(prefix.toUpperCase())) {
            suggestions.push({
              text: item.toLowerCase(),
              iconHTML: getImageURL(item)
            })
          }
        })
      // fields
      } else if (scopeDescriptor.getScopesArray()[7] == "punctuation.definition.string.end.json") {
        var newPrefix = getPrefix(editor, bufferPosition, scopeDescriptor)
        if (newPrefix) {
          if (newPrefix.key == 'key') {
            sortedPlaceholderArray.forEach(function(item) {
              if (item.includes(newPrefix.prefix.toUpperCase())) {
                suggestions.push({
                  text: item.toLowerCase(),
                  iconHTML: getImageURL(item)
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
      // what is this for?
      } else if (scopeDescriptor.getScopesArray()[4] == "punctuation.definition.string.end.json") {
        console.log("there")
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

function getImageURL(placeholder) {
  var imageURL
  var flags = 0b0
  if (placeholderJSON[placeholder].encompass === true) {
    flags += 0b1
  }
  if (placeholderJSON[placeholder].lqb === true) {
    flags += 0b10
  }
  if (placeholderJSON[placeholder].nmm === true) {
    flags += 0b100
  }

  switch(flags) {
    case 0b001:
      imageURL = encompassLogoImageURL
      break
    case 0b010:
      imageURL = lqbLogoImageURL
      break
    case 0b011:
    case 0b111:
      imageURL = encomplqbLogoImageURL
      break
    case 0b100:
      imageURL = nmmLogoImageURL
      break
    default:
      imageURL = snLogoImageURL
  }

  return imageURL
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
    iconHTML: snLogoImageURL,
    description: 'Boolean, but user must agree before proceeding'
  })

  snTypeSet.push({
    text: 'boolean',
    iconHTML: snLogoImageURL,
    description: 'Yes or No'
  })

  snTypeSet.push({
    text: 'currency',
    iconHTML: snLogoImageURL,
    description: 'Number but with currency validation'
  })

  snTypeSet.push({
    text: 'date',
    iconHTML: snLogoImageURL,
    description: 'Provides a date input'
  })

  snTypeSet.push({
    text: 'email',
    iconHTML: snLogoImageURL,
    description: 'Text but with email validation'
  })

  snTypeSet.push({
    text: 'info',
    iconHTML: snLogoImageURL,
    description: 'Displays text without requiring user input, and without a "Read More" button'
  })

  snTypeSet.push({
    text: 'integer',
    iconHTML: snLogoImageURL,
    description: 'Non-decimal numbers'
  })

  snTypeSet.push({
    text: 'multi_choice',
    iconHTML: snLogoImageURL,
    description: 'Checkbox group with choices defined in choices: []'
  })

  snTypeSet.push({
    text: 'phone',
    iconHTML: snLogoImageURL,
    description: 'Used for phone numbers'
  })

  snTypeSet.push({
    text: 'percentage',
    iconHTML: snLogoImageURL,
    description: 'Number with decimal'
  })

  snTypeSet.push({
    text: 'single_choice',
    iconHTML: snLogoImageURL,
    description: 'Dropdown box with choices defined in choices: []'
  })

  snTypeSet.push({
    text: 'ssn',
    iconHTML: snLogoImageURL,
    description: 'Integer, but with ssn validation'
  })

  snTypeSet.push({
    text: 'state',
    iconHTML: snLogoImageURL,
    description: 'Presents a state dropdown. To only show states where LO has lisence add allowAllStates: false'
  })

  snTypeSet.push({
    text: 'text',
    iconHTML: snLogoImageURL,
    description: 'Any valid text'
  })

  snTypeSet.push({
    text: 'zip',
    iconHTML: snLogoImageURL,
    description: 'Integer, but with zip validation'
  })

  return snTypeSet
}

function buildSnFieldSet() {
  var snFieldSet = []

  snFieldSet.push({
    text: 'name',
    iconHTML: snLogoImageURL,
    description: 'Name of the form you are creating (1003 Short Form, Pre-Qualification Form, Pre-Approval Form)'
  })

  snFieldSet.push({
    text: 'structure',
    iconHTML: snLogoImageURL,
    description: 'Contains the layout of the form, consisting of fields and instructions'
  })

  snFieldSet.push({
    text: 'values',
    iconHTML: snLogoImageURL,
    description: 'Any values you want to pre-determine'
  })

  snFieldSet.push({
    text: 'fields',
    iconHTML: snLogoImageURL,
    description: 'The definitions of the fields you used in structure'
  })

  snFieldSet.push({
    text: 'version',
    iconHTML: snLogoImageURL,
    description: 'Should pretty much always be 1.0'
  })

  return snFieldSet
}

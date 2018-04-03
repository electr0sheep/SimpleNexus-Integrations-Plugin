module.exports =
class snProvider {
  constructor(placeholderSet) {
    this.selector = '.text.html, .source.json'
    this.inclusionPriority = 1
    this.suggestionPriority = 2
    this.placeholderSet = placeholderSet
    this.imageURL = atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/simplenexus-icon-transparent.png'
  }

  getSuggestions({scopeDescriptor, prefix, editor, bufferPosition}) {
    const suggestions = []

    var iterator = this.placeholderSet.values()
    var value

    if (!(prefix != null ? prefix.length : undefined)) { return }

    // we need to figure out if we're working with JSON or HTML
    if (scopeDescriptor.getScopesArray().indexOf('text.html.basic') > -1) {
      var newPrefix = getPrefix(editor, bufferPosition, scopeDescriptor)
      if (newPrefix != null) {
        while (value = iterator.next().value) {
          if (value.startsWith(newPrefix.toUpperCase())) {
            suggestions.push({
              text: value,
              iconHTML: '<image src="' + this.imageURL + '"/>'
            })
          }
        }
      }
    } else if (scopeDescriptor.getScopesArray().indexOf('source.json') > -1) {
      if (scopeDescriptor.getScopesArray()[8] == "punctuation.definition.string.end.json") {
        while (value = iterator.next().value) {
          if (value.startsWith(prefix.toUpperCase())) {
            suggestions.push({
              text: value.toLowerCase(),
              iconHTML: '<image src="' + this.imageURL + '"/>'
            })
          }
        }
      } else if (scopeDescriptor.getScopesArray()[7] == "punctuation.definition.string.end.json") {
        var newPrefix = getPrefix(editor, bufferPosition, scopeDescriptor)
        if (newPrefix != null) {
          while (value = iterator.next().value) {
            if (value.startsWith(newPrefix.toUpperCase())) {
              suggestions.push({
                text: value.toLowerCase(),
                iconHTML: '<image src="' + this.imageURL + '"/>'
              })
            }
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

    return line.substring(nearestBracket + 1, bufferPosition.column)
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

    if (line.substring(semiColon - 5, semiColon) != "\"key\"") {
      return
    }

    return line.substring(semiColon + 3, bufferPosition.column)
  }
}

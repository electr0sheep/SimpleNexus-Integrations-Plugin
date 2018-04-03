module.exports =
class snProvider {
  // var placeholderSet = null

  constructor(placeholderSet) {
    this.selector = '.source.html, .source.json'
    this.inclusionPriority = 1
    this.suggestionPriority = 2
    this.placeholderSet = placeholderSet
  }

  getSuggestions({scopeDescriptor, prefix}) {
    const suggestions = []

    var iterator = this.placeholderSet.values()
    var value

    if (!(prefix != null ? prefix.length : undefined)) { return }

    // we need to figure out if we're working with JSON or HTML
    if (scopeDescriptor.getScopesArray().indexOf('source.html')) {
      if (scopeDescriptor.getScopesArray().indexOf("meta.structure.dictionary.value.json") == -1 || scopeDescriptor.getScopesArray().indexOf("string.quoted.double.json") == -1) { return }
      while (value = iterator.next().value) {
        if (value.startsWith(prefix.toUpperCase())) {
          console.log("pushing this")
          suggestions.push({
            text: value.toLowerCase()
          })
        }
      }
    } else if (scopeDescriptor.getScopesArray().indexOf('source.json')) {
      while (value = iterator.next().value) {
        if (value.startsWith(prefix.toUpperCase())) {
          console.log("pushing that")
          suggestions.push({
            text: value
          })
        }
      }
    }

    console.log(suggestions)
    return suggestions
  }
}

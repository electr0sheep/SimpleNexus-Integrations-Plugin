// http://www.mattzeunert.com/2016/01/28/javascript-deep-equal.html
// TODO: If a duplicate field has a mapping in structure, it isn't counted as duplicate
// TODO: It looks like cleaning creates a duplicate in fields and in partial duplicates
// TODO: What happens if the same file has multiple JSON documents?
// TODO: I think if the file hasn't been saved yet, there is a bug (toUpperCase of undefined)
var deepEqual = require('deep-equal')

module.exports = {
  beautifySimpleNexusJson: function (jsonFields) {
    let editor
    let nmm = atom.config.get("SimpleNexus-Integrations-Plugin.NMM")
    if (editor = atom.workspace.getActiveTextEditor()) {
      // check for JSON extension
      if (!editor.getPath().toUpperCase().endsWith(".JSON")) {
        atom.notifications.addError("SimpleNexus JSON Beautifier only works on JSON files!")
        return
      }
      let selection = editor.getText()
      try {
        var parsedJson = JSON.parse(editor.getText())
      }
      catch(err) {
        if (String(err).startsWith("SyntaxError: Unexpected token = in JSON")) {
          atom.notifications.addError("Couldn't parse JSON")
          atom.notifications.addError("It looks like you forgot to clean up extra fields after beautifying!")
        } else {
          atom.notifications.addError("Couldn't parse JSON")
          atom.notifications.addError(String(err))
          atom.notifications.addError("Check console for more information")
          console.log(err)
        }
        return
      }
      // verify that the JSON object is SimpleNexus JSON, first by checking for unknown fields
      for (var property in parsedJson) {
        if (property != 'name' && property != 'structure' && property != 'values' && property != 'fields' && property != 'version' && property != 'initially_skip_fields') {
          atom.notifications.addError("It looks like the JSON structure you are editing doesn't match SimpleNexus' JSON.")
          atom.notifications.addError("Field \'" + property + "\' is not a supported SimpleNexus JSON field")
          atom.notifications.addError("Aborting")
          return
        }
      }
      // then verify SimpleNexus JSON by checking for existence of fields
      if (!parsedJson.hasOwnProperty('name')) {
        atom.notifications.addError("It looks like the JSON structure you are editing doesn't match SimpleNexus' JSON.")
        atom.notifications.addError("SimpleNexus JSON must have a \'name\' field")
        return
      } else if (!parsedJson.hasOwnProperty('structure')) {
        atom.notifications.addError("It looks like the JSON structure you are editing doesn't match SimpleNexus' JSON.")
        atom.notifications.addError("SimpleNexus JSON must have a \'structure\' field")
        return
      } else if (!parsedJson.hasOwnProperty('values')) {
        atom.notifications.addError("It looks like the JSON structure you are editing doesn't match SimpleNexus' JSON.")
        atom.notifications.addError("SimpleNexus JSON must have a \'values\' field")
        return
      } else if (!parsedJson.hasOwnProperty('fields')) {
        atom.notifications.addError("It looks like the JSON structure you are editing doesn't match SimpleNexus' JSON.")
        atom.notifications.addError("SimpleNexus JSON must have a \'fields\' field")
        return
      } else if (!parsedJson.hasOwnProperty('version')) {
        atom.notifications.addError("It looks like the JSON structure you are editing doesn't match SimpleNexus' JSON.")
        atom.notifications.addError("SimpleNexus JSON must have a \'version\' field")
        return
      }
      if (nmm) {
        atom.notifications.addSuccess("🐵🍌🌰NMM Activated!🌰🍌🐵")
      }

      // I use JSON.parse(JSON.stringify(obj)) here to deep copy the objects
      var cleanedJson = {"name": JSON.parse(JSON.stringify(parsedJson.name)), "structure": JSON.parse(JSON.stringify(parsedJson.structure)), "values": JSON.parse(JSON.stringify(parsedJson.values)), "fields": [], "version": JSON.parse(JSON.stringify(parsedJson.version))}
      var unusedFields = JSON.parse(JSON.stringify(parsedJson.fields))
      var partialDuplicateFields = []
      var cleanedFieldsIndex = 0

      // first, clean duplicate fields out of unusedFields until no duplicates are found

      // oddly enough, cleaning duplicates turned out to be non-trivial.

      for (var i = 0; i < unusedFields.length; i++) {
        // check entry against partialDuplicateFields first
        for (var i2 = 0; i2 < partialDuplicateFields.length; i2++) {
          if (unusedFields[i].key == partialDuplicateFields[i2].key) {
            // make sure there isn't an exact match in partialDuplicateFields already
            let partialDuplicateExactMatch = false
            for (var i3 = i2; i3 < partialDuplicateFields.length; i3++) {
              if (deepEqual(unusedFields[i], partialDuplicateFields.length[i3])) {
                partialDuplicateExactMatch = true
                break
              }
            }

            if (partialDuplicateExactMatch === false) {
              partialDuplicateFields.push(JSON.parse(JSON.stringify(unusedFields[i])))
            }
            unusedFields.splice(i, 1)
            // we need to go back, because the field at i is now a new field
            i--
            continue
          }
        }

        // then check entry against other fields in unusedFields
        for (var i2 = i + 1; i2 < unusedFields.length; i2++) {
          if (unusedFields[i].key == unusedFields[i2].key) {
            if (!deepEqual(unusedFields[i], unusedFields[i2])) {
              partialDuplicateFields.push(JSON.parse(JSON.stringify(unusedFields[i])))
              partialDuplicateFields.push(JSON.parse(JSON.stringify(unusedFields[i2])))
              unusedFields.splice(i2, 1)
            }
            unusedFields.splice(i, 1)
            // we need to go back, because the field at i is now a new field
            i--
            break
          }
        }
      }

      // at this point, cleanedJson has a field that shouldn't be there
      console.log(partialDuplicateFields)
      console.log(unusedFields)
      console.log(cleanedJson)

      // we need to check for multi-phase loan apps
      if (parsedJson.structure[0].fields !== undefined) {
        // loop through the structure...
        for (var i = 0; i < parsedJson.structure.length; i++) {
          // and fields...
          if (parsedJson.structure[i].fields) {
            for (var i2 = 0; i2 < parsedJson.structure[i].fields.length; i2++) {
              var fieldExists = false
              var duplicate = false

              // make sure each field in structure has a matching field in fields
              for (var i3 = 0; i3 < parsedJson.fields.length; i3++) {
                if (parsedJson.structure[i].fields[i2] == parsedJson.fields[i3].key) {
                  fieldExists = true
                  break
                }
              }

              if (fieldExists === false) {
                // check for nmm
                if (nmm) {
                  // add the field
                  var nmmHasField
                  for (var i3 = 0; i3 < jsonFields.fields.length; i3++) {
                    nmmHasField = false
                    if (jsonFields.fields[i3].key == parsedJson.structure[i].fields[i2]) {
                      nmmHasField = true
                      cleanedJson.fields[cleanedFieldsIndex] = jsonFields.fields[i3]
                      cleanedFieldsIndex++
                      break
                    }
                  }
                  if (nmmHasField === false) {
                    atom.notifications.addError("NMM couldn't find \'" + parsedJson.structure[i].fields[i2] + "\' please create a new issue: https://github.com/electr0sheep/SimpleNexus-Integrations-Plugin/issues/new", {dismissable: true})
                  }
                } else {
                  atom.notifications.addWarning("Field \'" + parsedJson.structure[i].fields[i2] + "\' exists in structure, but not in fields")
                }
              } else {
                // look for duplicates in existing fields
                for (var i3 = 0; i3 < cleanedJson.fields.length; i3++) {
                  if (cleanedJson.fields[i3].key == parsedJson.structure[i].fields[i2]) {
                    duplicate = true
                    break
                  }
                }

                if (duplicate === false) {
                  var index = -1
                  // find index in pre-formatted JSON structure
                  for (var i3 = 0; i3 < parsedJson.fields.length; i3++) {
                    if (parsedJson.fields[i3].key == parsedJson.structure[i].fields[i2]) {
                      index = i3
                      break
                    }
                  }

                  // match field definitions with their order in the struct ure definition
                  cleanedJson.fields[cleanedFieldsIndex] = parsedJson.fields[index]

                  // finally, remove the field from unusedFields
                  for (var i3 = 0; i3 < unusedFields.length; i3++) {
                    if (unusedFields[i3].key == parsedJson.structure[i].fields[i2]) {
                      unusedFields.splice(i3, 1);
                    }
                  }
                  cleanedFieldsIndex++
                }
              }
            }
          }
        }
      }
      else {
        // loop through the structures...
        for (var i = 0; i < parsedJson.structure.length; i++) {
          for (var i2 = 0; i2 < parsedJson.structure[i].length; i2++) {
            // and fields...
            if (parsedJson.structure[i][i2].fields) {
              for (var i3 = 0; i3 < parsedJson.structure[i][i2].fields.length; i3++) {
                var fieldExists = false
                var duplicate = false

                // make sure each field in structure has a matching field in fields
                for (var i4 = 0; i4 < parsedJson.fields.length; i4++) {
                  if (parsedJson.structure[i][i2].fields[i3] == parsedJson.fields[i4].key) {
                    console.log("found field for " + parsedJson.structure[i][i2].fields[i3])
                    fieldExists = true
                    break
                  }
                }

                if (fieldExists === false) {
                  // check for nmm
                  if (nmm) {
                    // add the field
                    var nmmHasField
                    for (var i4 = 0; i4 < jsonFields.fields.length; i4++) {
                      nmmHasField = false
                      if (jsonFields.fields[i4].key == parsedJson.structure[i][i2].fields[i3]) {
                        nmmHasField = true
                        cleanedJson.fields[cleanedFieldsIndex] = jsonFields.fields[i4]
                        cleanedFieldsIndex++
                        break
                      }
                    }
                    if (nmmHasField === false) {
                      atom.notifications.addError("NMM couldn't find \'" + parsedJson.structure[i][i2].fields[i3] + "\' please create a new issue: https://github.com/electr0sheep/SimpleNexus-Integrations-Plugin/issues/new", {dismissable: true})
                    }
                  } else {
                    atom.notifications.addWarning("Field \'" + parsedJson.structure[i][i2].fields[i3] + "\' exists in structure, but not in fields")
                  }
                } else {
                  // look for duplicates in existing fields
                  for (var i4 = 0; i4 < cleanedJson.fields.length; i4++) {
                    if (cleanedJson.fields[i4].key == parsedJson.structure[i][i2].fields[i3]) {
                      console.log(cleanedJson.fields[i4].key + " is dupe")
                      duplicate = true
                      break
                    }
                  }

                  if (duplicate === false) {
                    console.log("adding " + parsedJson.fields[i4].key + " to fields")
                    var index = -1
                    // find index in pre-formatted JSON structure
                    for (var i4 = 0; i4 < parsedJson.fields.length; i4++) {
                      if (parsedJson.fields[i4].key == parsedJson.structure[i][i2].fields[i3]) {
                        index = i3
                        break
                      }
                    }

                    // match field definitions with their order in the structure definition
                    cleanedJson.fields[cleanedFieldsIndex] = parsedJson.fields[index]

                    // finally, remove the field from unusedFields
                    for (var i4 = 0; i4 < unusedFields.length; i4++) {
                      if (unusedFields[i4].key == parsedJson.structure[i][i2].fields[i3]) {
                        unusedFields.splice(i4, 1);
                      }
                    }
                    cleanedFieldsIndex++
                  }
                }
              }
            }
          }
        }
      }


      if ((parsedJson.fields.length - cleanedJson.fields.length - partialDuplicateFields.length - unusedFields.length) > 0) {
        atom.notifications.addSuccess("Removed " + (parsedJson.fields.length - cleanedJson.fields.length - partialDuplicateFields.length - unusedFields.length) + " duplicate field(s)")
      }
      if (unusedFields.length > 0) {
        atom.notifications.addSuccess("Found " + unusedFields.length + " unused field(s)")
      }
      if (partialDuplicateFields.length > 0) {
        atom.notifications.addSuccess("Found " + partialDuplicateFields.length + " partial duplicate(s)")
      }
      // I decided to take out the number of JSON lines that compose the unused fields...it would
      // need to be updated to include duplicate fields to be truly accurate anyway

      // if ((JSON.stringify(JSON.stringify(unusedFields, null, 2)).match(/\\n/g)||[]).length > 0) {
      //   atom.notifications.addSuccess("Found " + (JSON.stringify(JSON.stringify(unusedFields, null, 2)).match(/\\n/g)||[]).length + " excess lines of JSON")
      // }
      atom.notifications.addSuccess("SimpleNexus JSON Beautified!")
      editor.setText(JSON.stringify(cleanedJson, null, 2))

      // only print the last bit if something was removed
      // only print if NMM is not active
      if (!nmm) {
        if (unusedFields.length > 0) {
          editor.insertText("\n\n\n\n\n\n\n\n================================================================================\n")
          editor.insertText("|                                                                              |\n")
          editor.insertText("|                       THE FOLLOWING FIELDS WERE UNUSED                       |\n")
          editor.insertText("|                                                                              |\n")
          editor.insertText("================================================================================\n\n\n\n\n\n\n\n")
          editor.insertText(JSON.stringify(unusedFields, null, 2))
        }

        if (partialDuplicateFields.length > 0) {
          editor.insertText("\n\n\n\n\n\n\n\n================================================================================\n")
          editor.insertText("|                                                                              |\n")
          editor.insertText("|       THE FOLLOWING FIELDS HAD THE SAME KEY, BUT AREN'T TRUE DUPLICATES      |\n")
          editor.insertText("|                                                                              |\n")
          editor.insertText("================================================================================\n\n\n\n\n\n\n\n")
          editor.insertText(JSON.stringify(partialDuplicateFields, null, 2))
        }
      }
    }
  }
};

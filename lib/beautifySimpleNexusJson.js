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
          console.error(err)
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
      var nmmAddedFields = 0

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

      // Single phase
      if (parsedJson.structure[0] !== undefined && parsedJson.structure[0][0] === undefined) {
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
                      nmmAddedFields++
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
      // Multi-Phase
      else if (parsedJson.structure[0][0] !== undefined) {
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
                        nmmAddedFields++
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
                      var copyOfCleanedJson = JSON.parse(JSON.stringify(cleanedJson))
                      duplicate = true
                      break
                    }
                  }

                  if (duplicate === false) {
                    var index = -1
                    // find index in pre-formatted JSON structure
                    for (var i4 = 0; i4 < parsedJson.fields.length; i4++) {
                      if (parsedJson.fields[i4].key == parsedJson.structure[i][i2].fields[i3]) {
                        index = i4
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
      // there is no structure, just remove all the fields
      else {
        atom.notifications.addError("SimpleNexus-Integrations-Plugin doesn't support loan apps with no structure yet")
      }

      // Do SimpleNexus specific checks
      var has_errors = false

      // Check the structure
      if (cleanedJson.structure[0] !== undefined && cleanedJson.structure[0][0] === undefined) {
        for (var i = 0; i < cleanedJson.structure.length; i++) {
          let page = cleanedJson.structure[i]
          if (page.condition !== undefined) {
            for (var i2 = 0; i2 < page.fields.length; i2++) {
              let field = page.fields[i2]
              if (field == page.condition) {
                atom.notifications.addError("Page with instructions '" + page.instructions + "' has a field that is the same as the condition!", {dismissable: true})
                has_errors = true
              }
            }
          }
        }
      } else if (cleanedJson.structure[0][0] !== undefined) {
        for (var i = 0; i < cleanedJson.structure.length; i++) {
          let phase = cleanedJson.structure[i]
          for (var i2 = 0; i2 < phase.length; i2++) {
            let page = phase[i2]
            if (page.condition !== undefined) {
              for (var i3 = 0; i3 < page.fields.length; i3++) {
                let field = page.fields[i3]
                if (field == page.condition) {
                  atom.notifications.addError("Page with instructions '" + page.instructions + "' has a field that is the same as the condition!", {dismissable: true})
                  has_errors = true
                }
              }
            }
          }
        }
      }

      for (var i = 0; i < cleanedJson.fields.length; i++) {
        let currentField = cleanedJson.fields[i]

        // ERRORS
        // check for type
        if (currentField.type == undefined || currentField.type == "") {
          atom.notifications.addError("Field '" + currentField.key + "' doesn't have a type!", {dismissable: true})
          has_errors = true
        }

        // single choice check
        if (currentField.type == "single_choice") {
          // check for fields with no choices
          if (currentField.choices === undefined) {
            atom.notifications.addError("Field '" + currentField.key + "' is of single choice type but has no choices!", {dismissable: true})
            has_errors = true
          }
        }

        // multi choice checks
        if (currentField.type == "multi_choice") {
          // check for fields with no choices
          if (currentField.choices === undefined) {
            atom.notifications.addError("Field '" + currentField.key + "' is of multi choice type but has no choices!", {dismissable: true})
            has_errors = true
          }
        }

        // WARNINGS
        // check for blank fields
        for (var key in currentField) {
          if (currentField[key] === "") {
            if (nmm === false) {
              atom.notifications.addWarning("Key '" + key + "' in '" + currentField.key + "' is blank!")
            } else {
              delete currentField[key]
            }
          }
        }

        // check for title and description equivalence
        if (currentField.title && currentField.description && currentField.title == currentField.description) {
          if (nmm === false) {
            atom.notifications.addWarning("Field '" + currentField.key + "' has a description that is the same as it's title!")
          } else {
            delete currentField.description
          }
        }

        // check for equal min and max
        if (currentField.min != undefined && currentField.max != undefined && currentField.min == currentField.max) {
          if (nmm === false) {
            atom.notifications.addWarning("Field '" + currentField.key + "' has '" + currentField.min + "' set for both min and max!")
          } else {
            delete currentField.min
            delete currentField.max
          }
        }

        // check for no title on all types except info and verification of assets
        if (currentField.type != "info" && currentField.type != "verification_of_assets" && currentField.type != "info" && (currentField.title === undefined || currentField.title == "")) {
          atom.notifications.addWarning("Field '" + currentField.key + "' has no title!")
        }

        // state checks
        if (currentField.type == "state") {
          // property state shouldn't allow all states
          if (currentField.key == "property_state") {
            if (currentField.allowAllStates && currentField.allowAllStates == true) {
              atom.notifications.addWarning("Field '" + currentField.key + "' is subject property state, but allows all states!")
            }
            // all state fields except property state should allow all states
          } else {
            if (currentField.allowAllStates === undefined || (currentField.allowAllStates && currentField.allowAllStates == false)) {
              atom.notifications.addWarning("Field '" + currentField.key + "' is of state type but does not allow all states!")
            }
          }
        }

        // single choice checks
        if (currentField.type == "single_choice") {
          // check for fields with no blank option at the start
          if (currentField.choices && currentField.choices[0] != "") {
            if (nmm === false) {
              atom.notifications.addWarning("Field '" + currentField.key + "' is of single choice type but has no blank option!")
            } else {
              currentField.choices.unshift("")
            }
          }
        }

        // info checks
        if (currentField.type == "info"){
          // check for required info types
          if (currentField.required && currentField.required == true) {
            if (nmm === false) {
              atom.notifications.addWarning("Field '" + currentField.key + "' is of info type and is required!")
            } else {
              currentField.required = false
            }
          }
        }

        // date checks
        if (currentField.type == "date") {
          // check for description on date
          if (currentField.description) {
            if (nmm === false) {
              atom.notifications.addWarning("Field '" + currentField.key + "' is of date type and has a description. This description won't be visible!")
            } else {
              delete currentField.description
            }
          }
        }

        // phone checks
        if (currentField.type == "phone") {
          // check for min/max on phone
          if (currentField.min || currentField.max) {
            if (nmm === false) {
              atom.notifications.addWarning("Field '" + currentField.key + "' is of phone type and has either a min or max!")
            } else {
              delete currentField.min
              delete currentField.max
            }
          }
        }

      }

      if (has_errors) {
        return
      }

      if ((parsedJson.fields.length - cleanedJson.fields.length - partialDuplicateFields.length - unusedFields.length) > 0) {
        atom.notifications.addSuccess("Removed " + (parsedJson.fields.length - cleanedJson.fields.length - partialDuplicateFields.length - unusedFields.length) + " duplicate field(s)")
      }
      if (nmmAddedFields > 0) {
        atom.notifications.addSuccess("Added " + nmmAddedFields + " field(s)")
      }
      if (unusedFields.length > 0 && nmm == false) {
        atom.notifications.addError("Found " + unusedFields.length + " unused field(s)")
      } else if (unusedFields.length > 0 && nmm == true) {
        atom.notifications.addError("Removed " + unusedFields.length + " unused field(s)")
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

      // Organize "fields" fields
      var orderedJson = {}
      var unknownFields = false

      for (let field in cleanedJson) {
        if (field == "fields") {
          orderedJson[field] = []
          for (let values in cleanedJson[field]) {
            organizedField = {}
            if (cleanedJson[field][values].key != undefined) {
              organizedField.key = cleanedJson[field][values].key
            }
            if (cleanedJson[field][values].title != undefined) {
              organizedField.title = cleanedJson[field][values].title
            }
            if (cleanedJson[field][values].description != undefined) {
              organizedField.description = cleanedJson[field][values].description
            }
            if (cleanedJson[field][values].placeholder != undefined) {
              organizedField.placeholder = cleanedJson[field][values].placeholder
            }
            if (cleanedJson[field][values].text != undefined) {
              organizedField.text = cleanedJson[field][values].text
            }
            if (cleanedJson[field][values].min != undefined) {
              organizedField.min = cleanedJson[field][values].min
            }
            if (cleanedJson[field][values].max != undefined) {
              organizedField.max = cleanedJson[field][values].max
            }
            if (cleanedJson[field][values].type != undefined) {
              organizedField.type = cleanedJson[field][values].type
            }
            if (cleanedJson[field][values].header_text != undefined) {
              organizedField.header_text = cleanedJson[field][values].header_text
            }
            if (cleanedJson[field][values].primary_button_label != undefined) {
              organizedField.primary_button_label = cleanedJson[field][values].primary_button_label
            }
            if (cleanedJson[field][values].secondary_button_label != undefined) {
              organizedField.secondary_button_label = cleanedJson[field][values].secondary_button_label
            }
            if (cleanedJson[field][values].footer_text != undefined) {
              organizedField.footer_text = cleanedJson[field][values].footer_text
            }
            if (cleanedJson[field][values].allowAllStates != undefined) {
              organizedField.allowAllStates = cleanedJson[field][values].allowAllStates
            }
            if (cleanedJson[field][values].choices != undefined) {
              organizedField.choices = cleanedJson[field][values].choices
            }
            if (cleanedJson[field][values].indentations != undefined) {
              organizedField.indentations = cleanedJson[field][values].indentations
            }
            if (cleanedJson[field][values].required != undefined) {
              organizedField.required = cleanedJson[field][values].required
            }
            if (Object.keys(cleanedJson[field][values]).length != Object.keys(organizedField).length) {
              unknownFields = true
              for (let key in cleanedJson[field][values]) {
                if (organizedField[key] == undefined) {
                  console.log("Is " + key + " a valid entry for a " + organizedField.type + " type?")
                }
              }
            }
            orderedJson[field][values] = organizedField
          }
        } else {
          orderedJson[field] = JSON.parse(JSON.stringify(cleanedJson[field]))
        }
      }

      // only replace text if the text has changed
      if (editor.getText() !== JSON.stringify(orderedJson, null, 2) + '\n') {
        editor.setText(JSON.stringify(orderedJson, null, 2))
      }

      if (unknownFields) {
        atom.notifications.addWarning("Found unusual fields, check console")
      }

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

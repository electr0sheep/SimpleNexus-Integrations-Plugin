'use babel';

import { CompositeDisposable } from 'atom';

import { TouchBar, nativeImage } from 'remote';

const insertBoilerPlateFile = require('./insertBoilerPlateFile')
const beautifySimplenexusJson = require('./beautifySimpleNexusJson')
const showAvailablePlaceholders = require('./showAvailablePlaceholders')
const showModal = require('./showModal')
const snProvider = require('./snProvider')
const buildPlaceholderSet = require('./buildPlaceholderSet')

import { dispatchAction } from './dispatchAction';

let currentTouchBar;

export default {

  placeholders: null,

  provider: null,

  subscriptions: null,

  config: {
    "showConfirmationDialog": {
      "description": "If you attempt to over-write the contents of a file, shows a confirmation dialog before proceeding (default: true).",
      "type": "boolean",
      "default": true
    }
  },

  provide() {
    if (this.provider == null) {
      this.provider = new snProvider(this.placeholders)
    }

    return this.provider
  },

  activate(state) {
    // touchbar stuff
    configureButtons([{
      type: 'button',
      label: 'Beautify JSON',
      pathOfIcon: atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/simplenexus-icon-transparent.png',
      iconPosition: 'left',
      clickDispatchAction: 'sn-integrations-plugin:beautify'
    }], function(err, touchBarItems) {
      if (err) {
        atom.notifications.addError("The JSON renderer produced and error. Please check you configuration", {
          dismissable: true,
          detail: err
        });
      } else {
        console.log(touchBarItems);
        try {
          currentTouchBar = new TouchBar({items: touchBarItems});
        } catch(error) {
          console.log(error);
        }
      }
    });

    if (TouchBar) {
      atom.getCurrentWindow().setTouchBar(currentTouchBar);
    }

    // build placeholder set
    this.placeholders = buildPlaceholderSet.buildPlaceholderSet()

    // Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    this.subscriptions = new CompositeDisposable();

    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'sn-integrations-plugin:beautify': () => beautifySimplenexusJson.beautifySimpleNexusJson()
    }));

    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'sn-integrations-plugin:generate1003Json': () => insertBoilerPlateFile.insertSimpleNexusTextFromFile(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/defaultforms/1003/defaultform.json', "1003 JSON")
    }));

    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'sn-integrations-plugin:generatePrequalHtml': () => insertBoilerPlateFile.insertSimpleNexusTextFromFile(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/defaultforms/prequal/defaultform.html', "PreQual HTML")
    }));

    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'sn-integrations-plugin:generatePrequalJson': () => insertBoilerPlateFile.insertSimpleNexusTextFromFile(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/defaultforms/prequal/defaultform.json', "PreQual JSON")
    }));

    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'sn-integrations-plugin:generatePreapprovalHtml': () => insertBoilerPlateFile.insertSimpleNexusTextFromFile(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/defaultforms/preapproval/defaultform.html', "PreApproval HTML")
    }));

    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'sn-integrations-plugin:generatePreapprovalJson': () => insertBoilerPlateFile.insertSimpleNexusTextFromFile(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/defaultforms/preapproval/defaultform.json', "PreApproval JSON")
    }));

    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'sn-integrations-plugin:showAvailablePlaceholders': () => showAvailablePlaceholders.showAvailablePlaceholders(this.placeholders)
    }));
  },

  deactivate() {
    this.subscriptions.dispose();
  }
};

function configureButtons(itemsConfig, callback) {
  const {
    TouchBarButton,
    TouchBarColorPicker,
    TouchBarGroup,
    TouchBarLabel,
    TouchBarPopover,
    TouchBarScrubber,
    TouchBarSegmentedControl,
    TouchBarSlider,
    TouchBarSpacer
  } = TouchBar

  try {
    let items = [];

    itemsConfig.forEach(function(element) {
      let touchBarElement;
      switch (element.type) {
        case 'button':
          if (element.label && typeof element.label !== 'string')
            return callback(new Error("The button's label must be a string"));
          if (element.backgroundColor && typeof element.backgroundColor !== 'string')
            return callback(new Error("The button's backgroundColor must be a string"));
          if (element.pathOfIcon && typeof element.pathOfIcon !== 'string')
            return callback(new Error("The button's pathOfIcon must be a a string path pointing to PNG or JPEG file"));
          if (element.pathOfIcon && !element.iconPosition)
            return callback(new Error('If a button has an icon, it requires an iconPosition'));
          if (element.pathOfIcon && element.iconPosition && typeof element.iconPosition !== 'string')
            return callback(new Error("The button's iconPosition must be a string"));
          if (element.pathOfIcon && element.iconPosition && !(element.iconPosition == 'left' || element.iconPosition == 'overlay' || element.iconPosition == 'right'))
            return callback(new Error("The button's iconPosition can only be 'left', 'right' or 'overlay'"));
          if (element.click && typeof element.click !== 'function')
            return callback(new Error("The buttons's 'click' element must be a function"));

          if (element.clickDispatchAction && typeof element.clickDispatchAction !== 'string')
            return callback(new Error("The button's clickDispatchAction must be a string"));
          if (element.dispatchActionTarget && !(element.dispatchActionTarget == 'editor' || element.dispatchActionTarget == 'workspace'))
            return callback(new Error("The button's dispatchActionTarget must have a value of 'editor' or 'workspace'"));

          if (element.insertString && typeof element.insertString !== 'string') return callback(new Error("The button's insertString must be a string containing the set of characters to be inserted"));

          touchBarElement = new TouchBarButton({
            label: element.label,
            backgroundColor: element.backgroundColor,
            icon: element.pathOfIcon ?
              nativeImage.createFromPath(element.pathOfIcon) : undefined,
            iconPosition: element.iconPosition,
            click: element.insertString ? function() {
              Workspace.getActiveTextEditor().insertText(element.insertString) // The inseertCharacter will override the clickDispatchAction element
            } : (element.clickDispatchAction ?
              function() {
                dispatchAction(element.clickDispatchAction, element.dispatchActionTarget)
              } : element.click) // The clickDispatchAction will override the function of the 'click' element
          });
          break;

        case 'color-picker':
          if (element.availableColors && (!(element.availableColors instanceof Array) || !(element.availableColors.every(function(i) {
              return typeof i === "string"
            }))))
            return callback(new Error("The color-picker's availableColors must be a string of arrays"));
          if (element.selectedColor && typeof element.selectedColor !== 'string')
            return callback(new Error("The color-picker's selectedColor must be a string"));
          if (element.change && typeof element.change !== 'function')
            return callback(new Error("The color-picker's change must be a function"));

          touchBarElement = new TouchBarColorPicker({
            availableColors: element.availableColors,
            selectedColor: element.selectedColor,
            change: element.change
          });
          break;

        case 'group':
          if (!element.items || typeof element.items !== 'object' || !Array.isArray(element.items))
            return callback(new Error("The touch-bar-group's items must be an array of elements"));

          configureButtons(element.items, function(err, items) {
            if (err) {
              return callback(err);
            } else {
              if (items.length == 0)
                return callback(new Error('A Touch Bar group must contain at least one item'));
              touchBarElement = new TouchBarGroup({
                items: new TouchBar(items)
              });
            }
          });
          break;

        case 'label':
          if (element.label && typeof element.label !== 'string')
            return callback(new Error("The labels's label (text) must be a string"));
          if (element.textColor && typeof element.textColor !== 'string')
            return callback(new Error("The labels's textColor must be a string"));

          touchBarElement = new TouchBarLabel({
            label: element.label,
            textColor: element.textColor
          });
          break;

        case 'popover':
          if (element.label && typeof element.label !== 'string')
            return callback(new Error("The popover's label must be a string"));
          if (element.pathOfIcon && typeof element.pathOfIcon !== 'string')
            return callback(new Error("The popover's pathOfIcon must be a a string path pointing to PNG or JPEG file"));
          if (element.items && (typeof element.items !== 'object' || !Array.isArray(element.items)))
            return callback(new Error("The popover's items must be an array of elements"));
          if (element.showCloseButton && typeof element.showCloseButton !== 'boolean')
            return callback(new Error("The popover's showCloseButton must be a boolean"));

          configureButtons(element.items, function(err, items) {
            if (err) {
              return callback(err);
            } else {
              touchBarElement = new TouchBarPopover({
                label: element.label,
                icon: element.pathOfIcon ?
                  nativeImage.createFromPath(element.pathOfIcon) : undefined,
                items: new TouchBar(items),
                showCloseButton: element.showCloseButton
              });
            }
          });
          break;

          /*case 'scrubber':
          if(typeof element.select != 'function') return callback(new Error("The 'select' element of a touch-bar-scrubber must be a function"));
          if(typeof element.select != 'function') return callback(new Error("The 'select' element of a touch-bar-scrubber must be a function"));
          touchBarElement = new TouchBarScrubber({
            items: , // MISSING
            select: typeof element.select == 'function' ? element.select : undefined,
            highlight: typeof element.highlight == 'function'(highlightedIndex) => {

            },
            selectedStyle: ,
            overlayStyle: ,
            showArrowButtons: ,
            mode: ,
            continuous:
          });
          break;

        case 'segmented-control':
          if(element.segmentStyle && !(element.segmentStyle == 'automatic' || element.segmentStyle == 'rounded' || element.segmentStyle == 'textured-rounded' || element.segmentStyle == 'round-rect' || element.segmentStyle == 'textured-square' || element.segmentStyle == 'capsule' || element.segmentStyle == 'small-square' || element.segmentStyle == 'separated')) return callback(new Error("The button's iconPosition can only be 'automatic', 'rounded', 'textured-rounded', 'round-rect', 'textured-square', 'capsule', 'small-square' or 'separated'"));
          if(element.mode && !(element.mode == 'single' || element.mode == 'multiple' || element.mode == 'buttons')) return callback(new Error("The segmented-control's selectedIndex mus be an integer number"));
          if(!(element.segments instanceof Array) || !(element.availableColor.every(function(i){ return typeof i === "string" })) return callback(new Error("The color-picker's availableColors must be a string of arrays"));
          if(element.selectedIndex && !(typeof element.selectedIndex === 'number' || Number.isInteger(element.selectedIndex))) return callback(new Error("The slider's minValue must be an integer number"));
          if(typeof element.change != 'function') return callback(new Error("The 'change' element of a segmented-control must be a function"));

          touchBarElement = new TouchBarSegmentedControl({
            segmentStyle: elements.segmentStyle,
            mode: elements.mode,
            segments: ,
            selectedIndex: elements.selectedIndex,
            change: elements.change
          });
          break;*/

        case 'slider':
          if (element.label && typeof element.label !== 'string')
            return callback(new Error("The slider's label must be a string"));
          if (element.value && !(typeof element.value === 'number' || Number.isInteger(element.value)))
            return callback(new Error("The slider's value must be an integer number"));
          if (element.minValue && !(typeof element.minValue === 'number' || Number.isInteger(element.minValue)))
            return callback(new Error("The slider's minValue must be an integer number"));
          if (element.maxValue && !(typeof element.maxValue === 'number' || Number.isInteger(element.maxValue)))
            return callback(new Error("The slider's maxValue must be an integer number"));
          if (element.change && typeof element.change != 'function')
            return callback(new Error("The 'change' element of a TouchBarSlider must be a function"));

          touchBarElement = new TouchBarSlider({
            label: element.label,
            value: element.value,
            minValue: element.minValue,
            maxValue: element.maxValue,
            change: element.change
          });
          break;

        case 'spacer':
          if (element.size && !(element.size == 'small' || element.size == 'flexible' || element.size == 'large'))
            return callback(new Error("The spacer's size can only be 'small', 'flexible' or 'large'"));

          touchBarElement = new TouchBarSpacer({
            size: element.size
          });
          break;

        default:
          if (element.type === undefined) {
            return callback(new Error("The type of Touch Bar element isn't defined doesn't exist"));
          } else {
            return callback(new Error("The type of Touch Bar element '" + element.type + "' doesn't exist"));
          }
          break;
      }

      items.push(touchBarElement);
    });

    return callback(null, items);
  } catch (e) {
    return callback(e);
  }
}

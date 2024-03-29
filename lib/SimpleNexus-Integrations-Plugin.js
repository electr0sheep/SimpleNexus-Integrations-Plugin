'use babel';

import { CompositeDisposable } from 'atom';

import { TouchBar, nativeImage} from 'remote';

const insertBoilerPlateFile = require('./insertBoilerPlateFile')
const beautifySimpleNexusJson = require('./beautifySimpleNexusJson')
const addCondition = require('./addCondition')
const showAvailablePlaceholders = require('./showAvailablePlaceholders')
const showModal = require('./showModal')
const snProvider = require('./snProvider')
const buildPlaceholderSet = require('./buildPlaceholderSet')
const buildJSONFields = require('./buildJSONFields')
const usefulRegexes = require('./usefulRegexes')
const lineNumberView = require('./lineNumberView')

export default {

  placeholders: null,

  provider: null,

  subscriptions: null,

  config: {
    "showConfirmationDialog": {
      "title": "Show Confirmation Dialog",
      "description": "If you attempt to over-write the contents of a file, shows a confirmation dialog before proceeding (default: true).",
      "type": "boolean",
      "default": true
    },
    "NMM": {
      "title": "🐵🍌🌰Nutless Monkey Mode (NMM)🌰🍌🐵",
      "description": "With this option selected, when you beautify JSON files, it will automatically populate missing fields with values taken from SimpleNexus-Integrations-Plugin/simplenexus/default_json_fields.json and it will also automatically remove unused fields. Duplicate fields will still be shown at the bottom. Also, will automatically check for, and correct, strange 1003 elements i.e. a date field with a description, etc.",
      "type": "boolean",
      "default": false
    }
  },

  provide() {
    if (this.provider == null) {
      this.provider = new snProvider(this.placeholders)
    }

    return this.provider
  },

  activate(state) {
    // install useful packages
    require('atom-package-deps').install('SimpleNexus-Integrations-Plugin')

    // add more menu items if NMM is enabled
    atom.config.observe("SimpleNexus-Integrations-Plugin.NMM", function(value) {
      if (value === true) {
        this.nmmAddedMenuItems = atom.menu.add([{
          label: 'SimpleNexus Integrations Team',
          submenu: [{
            label: 'NMM'
          }]
        }])
        // this.nmmAddedMenuItems = atom.menu.add([{
        //   label: 'SimpleNexus Integrations Team',
        //   submenu : [{
        //     label: 'NMM', submenu : [{
        //       label: "Generate NMM JSON",
        //       command: 'hello:world'
        //     }]
        //   }]
        // }])
      } else {
        if (this.nmmAddedMenuItems) {
          this.nmmAddedMenuItems.dispose()
        }
      }

    })
    // touchbar stuff
    if (TouchBar) {
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
      var snBeautifyJSONTouchBarButton = new TouchBarButton({label: 'Beautify JSON', icon: nativeImage.createFromPath(atom.packages.getPackageDirPaths()[0] + '/SimpleNexus-Integrations-Plugin/simplenexus/images/simplenexus-icon-transparent.png'), iconPosition: 'left', click: function() { atom.commands.dispatch(atom.views.getView(atom.workspace.getActiveTextEditor()), 'SimpleNexus-Integrations-Plugin:beautify')}})
      // var snSegmentedControl = new TouchBarSegmentedControl({segments: [new TouchBarButton({enabled: false, icon: nativeImage.createFromPath(atom.packages.getPackageDirPaths()[0] + '/SimpleNexus-Integrations-Plugin/simplenexus/images/SimpleNexusLogoLarge.png').resize({height:5})})]})
      var snLogoTouchBarButton = new TouchBarButton({icon: nativeImage.createFromPath(atom.packages.getPackageDirPaths()[0] + '/SimpleNexus-Integrations-Plugin/simplenexus/images/SimpleNexusLogoLarge.png'), backgroundColor: '#FFFFFF'})

      // TouchBar demo items
      // var colorPicker = new TouchBarColorPicker({})
      // var touchBarGroup = new TouchBarGroup({items: new TouchBar([new TouchBarLabel({label: 'G1'}), new TouchBarLabel({label: 'G2'})])})
      // var touchBarLabel = new TouchBarLabel({label: 'Label', textColor: '#00E900'})
      // var touchBarPopover = new TouchBarPopover({label: 'Popover', items: new TouchBar([new TouchBarLabel({label: 'popover label 1'}), new TouchBarLabel({label: 'popover label 2'})])})
      // var touchBarScrubber = new TouchBarScrubber({items: [new TouchBarLabel({label: 'ScrubberItem1'}), new TouchBarLabel({label: 'ScrubberItem2'}), new TouchBarLabel({label: 'ScrubberItem3'}), new TouchBarLabel({label: 'ScrubberItem4'})], showArrowButtons: true})
      // var touchBarSegmentedControl = new TouchBarSegmentedControl({segments: [new TouchBarLabel({label: 'Segment 1'}), new TouchBarLabel({label: 'Segment 2'})], mode: 'multiple'})
      // var touchBarSlider = new TouchBarSlider({})
      // var touchBarSpacer = new TouchBarSpacer({})
      // var morePopover = new TouchBarPopover({label: 'More', items: new TouchBar([touchBarSegmentedControl, touchBarSpacer, touchBarSlider])})
      //
      // atom.getCurrentWindow().setTouchBar(new TouchBar({items: [snBeautifyJSONTouchBarButton, colorPicker, touchBarGroup, touchBarLabel, touchBarScrubber, morePopover]}))

      // end TouchBar demo items
      // var touchBar = new TouchBar({items: [snBeautifyJSONTouchBarButton]})
      // atom.getCurrentWindow().setTouchBar(snBeautifyJSONTouchBarButton)

      // scrolling text demo
      moveText([snLogoTouchBarButton, snBeautifyJSONTouchBarButton])
    }

    // build placeholder set
    this.placeholders = buildPlaceholderSet.buildPlaceholderSet()

    // build json fields
    this.jsonFields = buildJSONFields.build()

    // Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    this.subscriptions = new CompositeDisposable();

    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'SimpleNexus-Integrations-Plugin:beautify': () => beautifySimpleNexusJson.beautifySimpleNexusJson(this.jsonFields),
      'SimpleNexus-Integrations-Plugin:addCondition': () => addCondition.addCondition(),
      'SimpleNexus-Integrations-Plugin:generateSinglePhase1003Json': () => insertBoilerPlateFile.insertSimpleNexusTextFromFile(atom.packages.getPackageDirPaths()[0] + '/SimpleNexus-Integrations-Plugin/simplenexus/defaultforms/1003/SinglePhaseLoanAppTemplate.json', "Single Phase 1003 JSON"),
      'SimpleNexus-Integrations-Plugin:generateMultiPhase1003Json': () => insertBoilerPlateFile.insertSimpleNexusTextFromFile(atom.packages.getPackageDirPaths()[0] + '/SimpleNexus-Integrations-Plugin/simplenexus/defaultforms/1003/MultiPhaseLoanAppTemplate.json', "Multi Phase 1003 JSON"),
      'SimpleNexus-Integrations-Plugin:generatePrequalHtml': () => insertBoilerPlateFile.insertSimpleNexusTextFromFile(atom.packages.getPackageDirPaths()[0] + '/SimpleNexus-Integrations-Plugin/simplenexus/defaultforms/prequal/defaultform.html', "PreQual HTML"),
      'SimpleNexus-Integrations-Plugin:generatePrequalJson': () => insertBoilerPlateFile.insertSimpleNexusTextFromFile(atom.packages.getPackageDirPaths()[0] + '/SimpleNexus-Integrations-Plugin/simplenexus/defaultforms/prequal/defaultform.json', "PreQual JSON"),
      'SimpleNexus-Integrations-Plugin:generatePreapprovalHtml': () => insertBoilerPlateFile.insertSimpleNexusTextFromFile(atom.packages.getPackageDirPaths()[0] + '/SimpleNexus-Integrations-Plugin/simplenexus/defaultforms/preapproval/defaultform.html', "PreApproval HTML"),
      'SimpleNexus-Integrations-Plugin:generatePreapprovalJson': () => insertBoilerPlateFile.insertSimpleNexusTextFromFile(atom.packages.getPackageDirPaths()[0] + '/SimpleNexus-Integrations-Plugin/simplenexus/defaultforms/preapproval/defaultform.json', "PreApproval JSON"),
      'SimpleNexus-Integrations-Plugin:showAvailablePlaceholders': () => showAvailablePlaceholders.showAvailablePlaceholders(this.placeholders),
      'SimpleNexus-Integrations-Plugin:openSettings': () => atom.workspace.open("atom://config/packages/SimpleNexus-Integrations-Plugin"),
      'SimpleNexus-Integrations-Plugin:addBlankOptionToSingleChoice': () => usefulRegexes.addBlankOptionToSingleChoice(),
      'SimpleNexus-Integrations-Plugin:removeMinMaxWhenEqual': () => usefulRegexes.removeMinMaxWhenEqual(),
      'SimpleNexus-Integrations-Plugin:removeDuplicateDescriptions': () => usefulRegexes.removeDuplicateDescriptions(),
      'SimpleNexus-Integrations-Plugin:removeBlankFields': () => usefulRegexes.removeBlankFields(),
      'SimpleNexus-Integrations-Plugin:lineNumberView': () => new lineNumberView()
    }));
    this.subscriptions.add(atom.workspace.observeTextEditors(function(editor) {
      if (!editor.gutterWithName('relative-numbers')) {
        return new lineNumberView(editor);
      }
    }));
  },

  deactivate() {
    this.subscriptions.dispose();
  }
};

const moveText = (itemsArray) => {
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
  if (typeof moveText.touchBarLabel == 'undefined') {
    moveText.touchBarLabel = new TouchBarLabel({label: "Michael Rulez                                       "});
    itemsArray.push(moveText.touchBarLabel)
    atom.getCurrentWindow().setTouchBar(new TouchBar({items: itemsArray}));
  }
  setTimeout(moveText, 100);
  var str = moveText.touchBarLabel.label
  moveText.touchBarLabel.label = str.substr(str.length - 1) + str.slice(0,-1);
}

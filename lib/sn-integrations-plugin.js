'use babel';

import { CompositeDisposable } from 'atom';

import { TouchBar, nativeImage} from 'remote';

const insertBoilerPlateFile = require('./insertBoilerPlateFile')
const beautifySimplenexusJson = require('./beautifySimpleNexusJson')
const showAvailablePlaceholders = require('./showAvailablePlaceholders')
const showModal = require('./showModal')
const snProvider = require('./snProvider')
const buildPlaceholderSet = require('./buildPlaceholderSet')
const buildJSONFields = require('./buildJSONFields')

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
      "description": "With this option selected, when you beautify JSON files, it will automatically populate missing fields with values taken from sn-integrations-plugin/simplenexus/default_json_fields.json and it will also automatically remove unused fields. Duplicate fields will still be shown at the bottom.",
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
    require('atom-package-deps').install('sn-integrations-plugin')

    // add more menu items if NMM is enabled
    atom.config.observe("sn-integrations-plugin.NMM", function(value) {
      if (value === true) {
        this.nmmAddedMenuItems = atom.menu.add([{
          label: 'SimpleNexus Integrations Team',
          submenu : [{
            label: 'NMM', submenu : [{
              label: "Generate NMM JSON",
              command: 'hello:world'
            }]
          }]
        }])
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
      var snBeautifyJSONTouchBarButton = new TouchBarButton({label: 'Beautify JSON', icon: nativeImage.createFromPath(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/simplenexus-icon-transparent.png'), iconPosition: 'left', click: function() { atom.commands.dispatch(atom.views.getView(atom.workspace.getActiveTextEditor()), 'sn-integrations-plugin:beautify')}})
      // var snSegmentedControl = new TouchBarSegmentedControl({segments: [new TouchBarButton({enabled: false, icon: nativeImage.createFromPath(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/SimpleNexusLogoLarge.png').resize({height:5})})]})
      var snLogoTouchBarButton = new TouchBarButton({icon: nativeImage.createFromPath(atom.packages.getPackageDirPaths()[0] + '/sn-integrations-plugin/simplenexus/SimpleNexusLogoLarge.png'), backgroundColor: '#FFFFFF'})

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
      'sn-integrations-plugin:beautify': () => beautifySimplenexusJson.beautifySimpleNexusJson(this.jsonFields)
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

    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'sn-integrations-plugin:openSettings': () => atom.workspace.open("atom://config/packages/sn-integrations-plugin")
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

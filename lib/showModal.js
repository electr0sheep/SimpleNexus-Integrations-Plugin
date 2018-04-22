module.exports = {
  displayModal: function (newMessage) {
    var modalPanel;
    // Create root element
    this.element = document.createElement('div');
    this.element.classList.add('SimpleNexus-Integrations-Plugin');

    // Create message element
    const message = document.createElement('div');

    message.innerHTML = newMessage;

    message.classList.add('message');

    message.style.overflowY = "auto";
    message.style.maxHeight = "500px";

    const button = document.createElement('btn');
    button.style.marginTop = "20px";
    button.textContent = 'Okay';
    button.classList.add('btn');
    button.classList.add('btn-lg')
    button.classList.add('btn-primary');
    button.onclick = function () {
      modalPanel.destroy();
    }
    this.element.appendChild(message);
    this.element.appendChild(button);

    modalPanel = atom.workspace.addModalPanel({
      item: this.element,
      visible: false
    });
    modalPanel.show();
  }
}

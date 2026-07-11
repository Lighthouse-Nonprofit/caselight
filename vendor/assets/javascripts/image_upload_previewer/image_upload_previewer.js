class ImageUploadPreviewer {
  constructor(uploader, placeholder) {
    this.uploader = uploader;
    this.placeholder = placeholder;
  }

  perform() {
    const self = this;
    this._selectFileWhenPlaceholderClick();
    return this._showPreview();
  }

  _selectFileWhenPlaceholderClick() {
    const self = this;
    return $(this.placeholder).click(() => $(self.uploader).trigger('click'));
  }

  _showPreview() {
    const self = this;
    return $(this.uploader).change(function (e) {
      const { files } = e.target;
      if (FileReader && files && files.length) {
        const reader = new FileReader();
        reader.onload = () => (self.placeholder.src = reader.result);
        return reader.readAsDataURL(files[0]);
      } else {
        return alert("Your browser doesn't support file upload");
      }
    });
  }
}

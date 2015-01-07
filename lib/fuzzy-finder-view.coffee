path = require 'path'
{Point} = require 'atom'
{$, $$, SelectListView} = require 'atom-space-pen-views'
fs = require 'fs-plus'
filter = require './path-filter'

module.exports =
class FuzzyFinderView extends SelectListView
  filePaths: null
  projectRelativePaths: null

  initialize: ->
    super

    @addClass('fuzzy-finder')
    @setMaxItems(10)

    atom.commands.add @element,
      'pane:split-left': =>
        @splitOpenPath (pane, item) -> pane.splitLeft(items: [item])
      'pane:split-right': =>
        @splitOpenPath (pane, item) -> pane.splitRight(items: [item])
      'pane:split-down': =>
        @splitOpenPath (pane, item) -> pane.splitDown(items: [item])
      'pane:split-up': =>
        @splitOpenPath (pane, item) -> pane.splitUp(items: [item])

  getFilterKey: ->
    'projectRelativePath'

  destroy: ->
    @cancel()
    @panel?.destroy()

  viewForItem: ({filePath, projectRelativePath, result}) ->
    $$ ->
      @li class: 'two-lines', =>
        [repo] = atom.project.getRepositories()
        if repo?
          status = repo.getCachedPathStatus(filePath)
          if repo.isStatusNew(status)
            @div class: 'status status-added icon icon-diff-added'
          else if repo.isStatusModified(status)
            @div class: 'status status-modified icon icon-diff-modified'

        ext = path.extname(filePath)
        if fs.isReadmePath(filePath)
          typeClass = 'icon-book'
        else if fs.isCompressedExtension(ext)
          typeClass = 'icon-file-zip'
        else if fs.isImageExtension(ext)
          typeClass = 'icon-file-media'
        else if fs.isPdfExtension(ext)
          typeClass = 'icon-file-pdf'
        else if fs.isBinaryExtension(ext)
          typeClass = 'icon-file-binary'
        else
          typeClass = 'icon-file-text'

        fileBasename = path.basename(filePath)

        @div fileBasename, class: "primary-line file icon #{typeClass}", 'data-name': fileBasename, 'data-path': projectRelativePath
        if result
          @div class: 'secondary-line path no-icon', =>
            @raw result.match
          @div parseInt(result.score || 0, 10)
        else
          @div projectRelativePath, class: 'secondary-line path no-icon'

  openPath: (filePath, lineNumber) ->
    if filePath
      atom.workspace.open(filePath).done => @moveToLine(lineNumber)

  moveToLine: (lineNumber=-1) ->
    return unless lineNumber >= 0

    if textEditor = atom.workspace.getActiveTextEditor()
      position = new Point(lineNumber)
      textEditor.scrollToBufferPosition(position, center: true)
      textEditor.setCursorBufferPosition(position)
      textEditor.moveToFirstCharacterOfLine()

  splitOpenPath: (fn) ->
    {filePath} = @getSelectedItem() ? {}

    if @isQueryALineJump() and editor = atom.workspace.getActiveTextEditor()
      lineNumber = @getLineNumber()
      pane = atom.workspace.getActivePane()
      fn(pane, pane.copyActiveItem())
      @moveToLine(lineNumber)
    else if not filePath
      return
    else if pane = atom.workspace.getActivePane()
      atom.project.open(filePath).done (editor) =>
        fn(pane, editor)
        @moveToLine(lineNumber)
    else
      @openPath(filePath, lineNumber)

  populateList: ->
    if @isQueryALineJump()
      @list.empty()
      @setError('Jump to line in active editor')
    else
      return unless @items?

      filterQuery = @getFilterQuery()
      if filterQuery.length
        filteredItems = filter(filterQuery, @items,
          {
            key: @getFilterKey(),
            pre: "<b>",
            post: "</b>"
          }).map (v) ->
          res = v.original
          res.result = v.result
          res
      else
        filteredItems = @items

      @list.empty()
      if filteredItems.length
        @setError(null)

        for i in [0...Math.min(filteredItems.length, @maxItems)]
          item = filteredItems[i]
          itemView = $(@viewForItem(item))
          itemView.data('select-list-item', item)
          @list.append(itemView)

        @selectItemView(@list.find('li:first'))
      else
        @setError(@getEmptyMessage(@items.length, filteredItems.length))

  selectItemView: (view) ->
    super(view)

    return if !atom.config.get('fuzzy-finder-plus.enablePreview')

    {filePath} = @getSelectedItem()
    clearTimeout @previewTimeout if @previewTimeout
    self = this
    @previewTimeout = setTimeout ->
      self.openPreview(filePath)
    , 200

  openPreview: (filePath) ->
    @closePreview()

    pane = atom.workspace.activePane
    item = pane.itemForUri filePath
    if item
      pane.activateItem(item)
      return

    item = opener(atom.project.resolve(filePath), {}) for opener in atom.workspace.getOpeners() when !item
    return if item;

    e = atom.workspace.open filePath, activatePane: false
    @previewPath = filePath

  closePreview: ->
    pane = atom.workspace.activePane
    if @previewPath
      item = pane.itemForUri @previewPath
      pane.destroyItem item
      @previewPath = null


  confirmSelection: ->
    item = @getSelectedItem()
    @confirmed(item)

  confirmed: ({filePath}={}) ->
    if atom.workspace.getActiveTextEditor() and @isQueryALineJump()
      lineNumber = @getLineNumber()
      @cancel()
      @moveToLine(lineNumber)
    else if not filePath
      @cancel()
    else if fs.isDirectorySync(filePath)
      @setError('Selected path is a directory')
      setTimeout((=> @setError()), 2000)
    else
      lineNumber = @getLineNumber()
      @cancel()
      @openPath(filePath, lineNumber)

  isQueryALineJump: ->
    query = @filterEditorView.getModel().getText()
    colon = query.indexOf(':')
    trimmedPath = @getFilterQuery().trim()

    trimmedPath is '' and colon isnt -1

  getFilterQuery: ->
    query = super
    colon = query.indexOf(':')
    query = query[0...colon] if colon isnt -1
    # Normalize to backslashes on Windows
    query = query.replace(/\//g, '\\') if process.platform is 'win32'
    query

  getLineNumber: ->
    query = @filterEditorView.getText()
    colon = query.indexOf(':')
    if colon is -1
      -1
    else
      parseInt(query[colon+1..]) - 1

  setItems: (filePaths) ->
    super(@projectRelativePathsForFilePaths(filePaths))

  projectRelativePathsForFilePaths: (filePaths) ->
    # Don't regenerate project relative paths unless the file paths have changed
    if filePaths isnt @filePaths
      @filePaths = filePaths
      @projectRelativePaths = @filePaths.map (filePath) ->
        projectRelativePath = atom.project.relativize(filePath)
        {filePath, projectRelativePath}

    @projectRelativePaths

  show: ->
    @storeFocusedElement()
    @panel ?= atom.workspace.addModalPanel(item: this)
    @panel.show()
    @focusFilterEditor()

  hide: ->
    @closePreview()
    @panel?.hide()

  cancelled: ->
    @hide()

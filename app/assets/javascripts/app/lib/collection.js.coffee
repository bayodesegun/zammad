class App.Collection
  _instance = undefined

  @init: ->
    _instance = new _Singleton

  @load: ( args ) ->
    if _instance == undefined
      _instance ?= new _Singleton
    _instance.load( args )

  @find: ( type, id, callback, force ) ->
    if _instance == undefined
      _instance ?= new _Singleton
    _instance.find( type, id, callback, force )

  @get: ( args ) ->
    if _instance == undefined
      _instance ?= new _Singleton
    _instance.get( args )

  @all: ( type ) ->
    if _instance == undefined
      _instance ?= new _Singleton
    _instance.all( type )

  @deleteAll: ( type ) ->
    if _instance == undefined
      _instance ?= new _Singleton
    _instance.deleteAll( type )

  @findByAttribute: ( type, key, value ) ->
    if _instance == undefined
      _instance ?= new _Singleton
    _instance.findByAttribute( type, key, value )

  @count: ( type ) ->
    if _instance == undefined
      _instance ?= new _Singleton
    _instance.count( type )

  @fetch: ( type ) ->
    if _instance == undefined
      _instance ?= new _Singleton
    _instance.fetch( type )

class _Singleton

  constructor: (@args) ->

    # add trigger - bind new events
    Spine.bind 'loadCollection', (data) =>

      # load collections
      if data.collections
        for type of data.collections

          console.log 'loadCollection:trigger', type, data.collections[type]
          @load( localStorage: data.localStorage, type: type, data: data.collections[type] )

    # find collections to load
    @_loadCollectionAll()

  _loadCollectionAll: ->
    list = App.Store.list()
    for key in list
      parts = key.split('::')
      if parts[0] is 'collection'
        data = App.Store.get( key )
        if data && data.localStorage
          console.log('load INIT', data)
          @load( data )

  load: (params) ->
    console.log( 'load', params )

    return if _.isEmpty( params.data )

    localStorage = params.localStorage

    if _.isArray( params.data )
      for object in params.data
#        console.log( 'load ARRAY', object)
        if !localStorage || localStorage && !App[ params.type ].exists( object['id'] )
          App[ params.type ].refresh( object, options: { clear: true } )

        # remember in store if not already requested from local storage
        if !localStorage
          App.Store.write( 'collection::' + params.type + '::' + object.id, { type: params.type, localStorage: true, data: [ object ] } )
      return

#    if _.isObject( params.data )
    for key, object of params.data
#      console.log( 'load OB', object)
      if !localStorage || localStorage && !App[ params.type ].exists( object['id'] )
        App[ params.type ].refresh( object, options: { clear: true } )

      # remember in store if not already requested from local storage
      if !localStorage
        App.Store.write( 'collection::' + params.type + '::' + object.id, { type: params.type, localStorage: true, data: [ object ] } )

  find: ( type, id, callback, force ) ->

#    console.log( 'find', type, id, force )
#    if App[type].exists( id ) && !callback
    if !force && App[type].exists( id )
#      console.log( 'find exists', type, id )
      data = App[type].find( id )
      if callback
        callback( data )
    else
      if force
        console.log( 'find forced to load!', type, id )
      else
        console.log( 'find not loaded!', type, id )
      if callback
        App[type].bind 'refresh', ->
          console.log 'loaded..' + type +  '..', id
          App[type].unbind 'refresh'
          data = App.Collection.find( type, id )
          callback( data )
        console.log 'loading..' + type +  '..', id
        App[type].fetch( id: id )
        return true
      return false

   # users
    if type == 'User'

      # set socal media links
      if data['accounts']
        for account of data['accounts']
          if account == 'twitter'
            data['accounts'][account]['link'] = 'http://twitter.com/' + data['accounts'][account]['username']
          if account == 'facebook'
            data['accounts'][account]['link'] = 'https://www.facebook.com/profile.php?id=' + data['accounts'][account]['uid']

      # set image url
      if data && !data['image']
        data['image'] = 'http://placehold.it/48x48'

      return data

    # tickets
    else if type == 'Ticket'

      # priority
      data.ticket_priority = @find( 'TicketPriority', data.ticket_priority_id )

      # state
      data.ticket_state = @find( 'TicketState', data.ticket_state_id )

      # group
      data.group = @find( 'Group', data.group_id )

      # customer
      if data.customer_id
        data.customer = @find( 'User', data.customer_id )

      # owner
      if data.owner_id
        data.owner = @find( 'User', data.owner_id )

      # add created & updated
      if data.created_by_id
        data.created_by = @find( 'User', data.created_by_id )
      if data.updated_by_id
        data.updated_by = @find( 'User', data.updated_by_id )

      return data

    # articles
    else if type == 'TicketArticle'

      # add created & updated
      data.created_by = @find( 'User', data.created_by_id )

      # add possible actions
      data.article_type = @find( 'TicketArticleType', data.ticket_article_type_id )
      data.article_sender = @find( 'TicketArticleSender', data.ticket_article_sender_id )

      return data

    # history
    else if type == 'History'

      # add user
      data.created_by = @find( 'User', data.created_by_id )

      # add possible actions
      if data.history_attribute_id
        data.attribute = @find( 'HistoryAttribute', data.history_attribute_id )
      if data.history_type_id
        data.type      = @find( 'HistoryType', data.history_type_id )
      if data.history_object_id
        data.object    = @find( 'HistoryObject', data.history_object_id )

      return data

    else
      return data

  get: (params) ->
    console.log('get')
    App[params.type].refresh( object, options: { clear: true } )

  all: (type) ->
    all = App[type].all()
    all_complied = []
    for item in all
      item_new = @find( type, item.id )
      all_complied.push item_new
    return all_complied

  deleteAll: (type) ->
    App[type].deleteAll()

  findByAttribute: ( type, key, value ) ->
    App[type].findByAttribute( key, value )

  count: ( type ) ->
    App[type].count()

  fetch: ( type ) ->
    App[type].fetch()

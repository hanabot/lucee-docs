component extends="builders.html.Builder" {

// PUBLIC API
	public void function build( docTree, buildDirectory ) {
		var docsetRoot    = arguments.buildDirectory & "/lucee.docset/";
		var contentRoot   = docsetRoot & "Contents/";
		var resourcesRoot = contentRoot & "Resources/";
		var docsRoot      = resourcesRoot & "Documents/";
		var ignorePages   = { "download": true };

		var pagePaths = arguments.docTree.getPageCache().getPages();

		request.filesWritten = 0;
		request.filesToWrite = StructCount(pagePaths);
		request.logger (text="Builder Dash directory: #arguments.buildDirectory#");

		if ( !DirectoryExists( arguments.buildDirectory ) ) { DirectoryCreate( arguments.buildDirectory ); }
		if ( !DirectoryExists( docsetRoot               ) ) { DirectoryCreate( docsetRoot               ); }
		if ( !DirectoryExists( contentRoot              ) ) { DirectoryCreate( contentRoot              ); }
		if ( !DirectoryExists( resourcesRoot            ) ) { DirectoryCreate( resourcesRoot            ); }
		if ( !DirectoryExists( docsRoot                 ) ) { DirectoryCreate( docsRoot                 ); }

		try {
			_setupSqlLite( resourcesRoot );
			_setAutoCommit(false);
			for ( var path in pagePaths ) {
				if ( !ignorePages.keyExists( pagePaths[path].page.getId() ) ) {
					_writePage( pagePaths[path].page, arguments.buildDirectory & "/", docTree );
					request.filesWritten++;
					if ((request.filesWritten mod 100) eq 0)
						request.logger("Rendering Documentation (#request.filesWritten# / #request.filesToWrite#)");
					_storePageInSqliteDb( pagePaths[path].page );
				}
			}
			_setAutoCommit(true);
		} catch ( any e ) {
			rethrow;
		} finally {
			_closeDbConnection();
		}
		request.logger (text="Dash Builder #request.filesWritten# files produced");
		_copyResources( docsetRoot );
		_renameSqlLiteDb( resourcesRoot );
		_setupFeedXml( arguments.buildDirectory & "/" );
	}

	public string function renderLink( any page, required string title ) {

		if ( IsNull( arguments.page ) ) {
			return '<a class="missing-link">#HtmlEditFormat( arguments.title )#</a>';
		}

		var link = arguments.page.getId() & ".html";

		return '<a href="#link#">#HtmlEditFormat( arguments.title )#</a>';
	}

// PRIVATE HELPERS
	private string function _getHtmlFilePath( required any page, required string buildDirectory ) {
		if ( arguments.page.getPath() == "/home" ) {
			return arguments.buildDirectory & "/index.html";
		}

		return arguments.buildDirectory & arguments.page.getId() & ".html";
	}

	private void function _copyResources( required string rootDir ) {
		FileCopy( "/builders/dash/resources/Info.plist", arguments.rootDir & "Contents/Info.plist" );
		FileCopy( "/builders/dash/resources/icon.png", arguments.rootDir & "icon.png" );
		DirectoryCopy( "/builders/html/assets/css/", arguments.rootDir & "Contents/Resources/Documents/assets/css", true, "*", true );
		DirectoryCopy( "/builders/html/assets/images/", arguments.rootDir & "Contents/Resources/Documents/assets/images", true, "*", true );
		DirectoryCopy( "/docs/_images/", arguments.rootDir & "Contents/Resources/Documents/images", true, "*", true );
	}

	private void function _setupSqlLite( required string rootDir ) {
		variables.sqlite = _getSqlLiteCfc();
		variables.dbFile = sqlite.createDb( dbName="docSet", destDir=arguments.rootDir & "/" );
		variables.dbConnection  = sqlite.getConnection( dbFile );

		sqlite.executeSql( dbFile, "CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT)", false, dbConnection );
		sqlite.executeSql( dbFile, "CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path)", false, dbConnection );
	}

	private any function _getSqlLiteCfc() {
		return new api.sqlitecfc.SqliteCFC(
			  tempdir        = ExpandPath( "/api/sqlitecfc/tmp/" )
			, libdir         = ExpandPath( "/api/sqlitecfc/lib/" )
			, model_path     = "/api/sqlitecfc"
			, dot_model_path = "api.sqlitecfc"
		);
	}

	private void function _storePageInSqliteDb( required any page ) {
		var data = {};

		switch( page.getPageType() ){
			case "function":
				data = { name=page.getTitle(), type="Function" };
				break;
			case "tag":
				data = { name="cf" & page.getSlug(), type="Tag" };
				break;
			case "_object":
				data = { name=page.getTitle(), type="Object" };
				break;
			case "_method":
				data = { name=page.getTitle(), type="Method" };
				break;
			case "category":
				data = { name=Replace( page.getTitle(), "'", "''", "all" ), type="Category" };
				break;
			default:
				data = { name=Replace( page.getTitle(), "'", "''", "all" ), type="Guide" };
		}

		data.path = page.getId() & ".html";

		sqlite.executeSql( dbFile, "INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('#data.name#', '#data.type#', '#data.path#')", false, dbConnection );
	}

	private void function _closeDbConnection() {
		if ( StructKeyExists( variables, "dbConnection" ) ) {
			dbConnection.close();
		}
	}

	private void function _setAutoCommit(required boolean autoCommit) {
		if ( StructKeyExists( variables, "dbConnection" ) ) {
			dbConnection.setAutoCommit(arguments.autocommit);
		} else {
			throw message="_setAutoCommit: no active sqlLite dbConnection";
		}
	}

	private void function _renameSqlLiteDb( required string rootDir ) {
		FileMove( rootDir & "docSet.db", rootDir & "docSet.dsidx" );
	}

	private void function _setupFeedXml( required string rootDir ) {
		var feedXml = FileRead( "/builders/dash/resources/feed.xml" );
		var buildProps = new api.build.BuildProperties();

		feedXml = Replace( feedXml, "{url}"    , buildProps.getDashDownloadUrl(), "all" );
		feedXml = Replace( feedXml, "{version}", buildProps.getDashBuildNumber(), "all" );

		FileWrite( arguments.rootDir & "lucee.xml", feedXml );

	}
}
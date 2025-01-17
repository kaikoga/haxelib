import haxe.unit.*;
import haxe.*;
import haxe.io.*;
import sys.*;
import sys.io.*;
import haxelib.*;
using StringTools;
using IntegrationTests;

typedef UserRegistration = {
	user:String,
	email:String,
	fullname:String,
	pw:String
}

class IntegrationTests extends TestBase {
	static var projectRoot:String = Sys.getCwd();
	var haxelibBin:String = Path.join([projectRoot, "run.n"]);
	public var server(default, null):String = switch (Sys.getEnv("HAXELIB_SERVER")) {
		case null:
			"localhost";
		case url:
			url;
	};
	public var serverPort(default, null) = switch (Sys.getEnv("HAXELIB_SERVER_PORT")) {
		case null:
			2000;
		case port:
			Std.parseInt(port);
	};
	public var serverUrl(get, null):String;
	function get_serverUrl() return serverUrl != null ? serverUrl : serverUrl = 'http://${server}:${serverPort}/';

	static var originalRepo(default, never) = {
		var p = new Process("haxelib", ["--global", "config"]);
		var originalRepo = Path.normalize(p.stdout.readLine());
		p.close();
		if (repo == originalRepo) {
			throw "haxelib repo is the same as test repo: " + repo;
		}
		originalRepo;
	};
	static public var repo(default, never) = "repo_integration_tests";
	static public var bar(default, never):UserRegistration = {
		user: "Bar",
		email: "bar@haxe.org",
		fullname: "Bar",
		pw: "barpassword",
	};
	static public var foo(default, never):UserRegistration = {
		user: "Foo",
		email: "foo@haxe.org",
		fullname: "Foo",
		pw: "foopassword",
	};
	static public var deepAuthor(default, never):UserRegistration = {
		user: "DeepAuthor",
		email: "deep@haxe.org",
		fullname: "Jonny Deep",
		pw: "deep thought"
	}
	static public var anotherGuy(default, never):UserRegistration = {
		user: "AnotherGuy",
		email: "another@email.com",
		fullname: "Another Guy",
		pw: "some other pw"
	}
	public var clientVer(get, null):SemVer;
	var clientVer_inited = false;
	function get_clientVer() {
		return if (clientVer_inited)
			clientVer;
		else {
			clientVer = {
				var r = haxelib(["version"]).result();
				if (r.code == 0)
					SemVer.ofString(switch(r.out.trim()) {
						case _.split(" ") => [v] | [v, _]: v;
						case v: v;
					});
				else if (r.out.indexOf("3.1.0-rc.4") >= 0)
					SemVer.ofString("3.1.0-rc.4");
				else
					throw "unknown version";
			};
			clientVer_inited = true;
			clientVer;
		}
	}

	function haxelib(args:Array<String>, ?input:String):Process {
		var p = #if system_haxelib
			new Process("haxelib", ["-R", serverUrl].concat(args));
		#else
			new Process("neko", [haxelibBin, "--global", "-R", serverUrl].concat(args));
		#end

		if (input != null) {
			p.stdin.writeString(input);
			p.stdin.close();
		}

		return p;
	}

	function assertSuccess(r:{out:String, err:String, code:Int}, ?pos:haxe.PosInfos):Void {
		if (r.code != 0) {
			throw r;
		}
		assertEquals(0, r.code, pos);
	}

	function assertFail(r:{out:String, err:String, code:Int}, ?pos:haxe.PosInfos):Void {
		assertTrue(r.code != 0, pos);
	}

	function assertNoError(f:Void->Void):Void {
		f();
		assertTrue(true);
	}

	var dbConfig:Dynamic = Json.parse(File.getContent("www/dbconfig.json"));
	var dbCnx:sys.db.Connection;
	function resetDB():Void {
		var db = dbConfig.database;
		dbCnx.request('DROP DATABASE IF EXISTS ${db};');
		dbCnx.request('CREATE DATABASE ${db};');

		var filesPath = "www/files/3.0";
		for (item in FileSystem.readDirectory(filesPath)) {
			if (item.endsWith(".zip")) {
				FileSystem.deleteFile(Path.join([filesPath, item]));
			}
		}
		var tmpPath = "tmp";
		for (item in FileSystem.readDirectory(filesPath)) {
			if (item.endsWith(".tmp")) {
				FileSystem.deleteFile(Path.join([tmpPath, item]));
			}
		}
	}

	override function setup():Void {
		super.setup();

		dbCnx = sys.db.Mysql.connect({
			user: dbConfig.user,
			pass: dbConfig.pass,
			host: server,
			port: dbConfig.port,
			database: dbConfig.database,
		});
		resetDB();

		deleteDirectory(repo);
		FileSystem.createDirectory(repo);
		haxelibSetup(repo);

		Sys.setCwd(Path.join([projectRoot, "test"]));
	}

	override function tearDown():Void {
		Sys.setCwd(projectRoot);

		haxelibSetup(originalRepo);
		deleteDirectory(repo);

		resetDB();
		dbCnx.close();

		super.tearDown();
	}

	static public function result(p:Process):{out:String, err:String, code:Int} {
		var out = p.stdout.readAll().toString();
		var err = p.stderr.readAll().toString();
		var code = p.exitCode();
		p.close();
		return {out:out, err:err, code:code};
	}

	static public function haxelibSetup(path:String):Void {
		HaxelibTests.runCommand("haxelib", ["setup", path]);
	}

	static function main():Void {
		var prevDir = Sys.getCwd();

		var runner = new TestRunner();
		runner.add(new tests.integration.TestEmpty());
		runner.add(new tests.integration.TestSetup());
		runner.add(new tests.integration.TestSimple());
		runner.add(new tests.integration.TestUpgrade());
		runner.add(new tests.integration.TestUpdate());
		runner.add(new tests.integration.TestList());
		runner.add(new tests.integration.TestSet());
		runner.add(new tests.integration.TestInfo());
		runner.add(new tests.integration.TestUser());
		runner.add(new tests.integration.TestOwner());
		runner.add(new tests.integration.TestDev());
		var success = runner.run();

		if (!success) {
			Sys.exit(1);
		}
	}
}

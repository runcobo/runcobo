require "./database"

module Runcobo::Tasks
  class Schema
    CATALOG = <<-'SQL'
SELECT jsonb_build_object(
 'relations', (SELECT jsonb_agg(jsonb_build_array(c.relname, c.relkind, c.relpersistence, c.relrowsecurity, c.relforcerowsecurity, c.reloptions, obj_description(c.oid)) ORDER BY c.relname)
   FROM pg_class c WHERE c.relnamespace = :schema::regnamespace AND c.relkind IN ('r','p','S','v','m')),
 'columns', (SELECT jsonb_agg(jsonb_build_array(c.relname, a.attname,
   format_type(a.atttypid,a.atttypmod), a.attnotnull, a.attidentity, a.attgenerated,
   pg_get_expr(d.adbin,d.adrelid), col_description(c.oid,a.attnum)) ORDER BY c.relname,a.attnum)
   FROM pg_class c JOIN pg_attribute a ON a.attrelid=c.oid
   LEFT JOIN pg_attrdef d ON d.adrelid=c.oid AND d.adnum=a.attnum
   WHERE c.relnamespace=:schema::regnamespace AND c.relkind IN ('r','p','v','m') AND a.attnum>0 AND NOT a.attisdropped),
 'constraints', (SELECT jsonb_agg(jsonb_build_array(c.relname,k.conname,k.contype,pg_get_constraintdef(k.oid),k.convalidated,obj_description(k.oid))
   ORDER BY c.relname,k.conname) FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid WHERE c.relnamespace=:schema::regnamespace),
 'indexes', (SELECT jsonb_agg(jsonb_build_array(t.relname,c.relname,pg_get_indexdef(c.oid),i.indisvalid,obj_description(c.oid))
   ORDER BY t.relname,c.relname) FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid
   JOIN pg_class t ON t.oid=i.indrelid WHERE t.relnamespace=:schema::regnamespace),
 'sequences', (SELECT jsonb_agg(jsonb_build_array(c.relname,s.seqtypid::regtype::text,s.seqstart,s.seqincrement,s.seqmax,s.seqmin,s.seqcache,s.seqcycle,
   owner.relname,a.attname) ORDER BY c.relname) FROM pg_sequence s JOIN pg_class c ON c.oid=s.seqrelid
   LEFT JOIN pg_depend d ON d.objid=c.oid AND d.classid='pg_class'::regclass AND d.refclassid='pg_class'::regclass AND d.deptype IN ('a','i') AND d.refobjsubid>0
   LEFT JOIN pg_class owner ON owner.oid=d.refobjid LEFT JOIN pg_attribute a ON a.attrelid=owner.oid AND a.attnum=d.refobjsubid
   WHERE c.relnamespace=:schema::regnamespace),
 'views', (SELECT jsonb_agg(jsonb_build_array(c.relname,pg_get_viewdef(c.oid)) ORDER BY c.relname)
   FROM pg_class c WHERE c.relnamespace=:schema::regnamespace AND c.relkind IN ('v','m')),
 'functions', (SELECT jsonb_agg(jsonb_build_array(p.proname,pg_get_functiondef(p.oid)) ORDER BY p.proname,pg_get_function_identity_arguments(p.oid))
   FROM pg_proc p WHERE p.pronamespace=:schema::regnamespace AND p.prokind IN ('f','p')),
 'enums', (SELECT jsonb_agg(jsonb_build_array(t.typname,e.enumlabel,e.enumsortorder) ORDER BY t.typname,e.enumsortorder)
   FROM pg_type t JOIN pg_enum e ON e.enumtypid=t.oid WHERE t.typnamespace=:schema::regnamespace),
 'triggers', (SELECT jsonb_agg(jsonb_build_array(c.relname,t.tgname,pg_get_triggerdef(t.oid)) ORDER BY c.relname,t.tgname)
   FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relnamespace=:schema::regnamespace AND NOT t.tgisinternal)
)::text
SQL

    def initialize(@database : Database, @output : IO = STDOUT)
    end

    def sql(url : String, source : String) : String
      @database.psql(url, source).output.strip
    end

    def migration_source(paths : Array(Path)) : String
      paths.map do |path|
        source = File.read(path)
        if /\bpublic"?\s*\.|\b(?:CREATE|DROP|ALTER)\s+SCHEMA\b|\bSET\s+(?:LOCAL\s+)?search_path\b|^\s*\\/im.matches?(source)
          raise ArgumentError.new("Schema replay requires unqualified, schema-local migration statements")
        end
        source
      end.join("\n")
    end

    def apply_files(url : String, schema : String, paths : Array(Path))
      sql(url, %(SET search_path TO "#{schema}", pg_catalog;\n) + migration_source(paths))
    end

    def replay(url : String, paths : Array(Path), &)
      name = @database.settings.database_prefix + "_verify_" + UUID.random.to_s.delete('-')
      source = migration_source(paths)
      sql(url, %(CREATE SCHEMA "#{name}"))
      begin
        sql(url, %(SET search_path TO "#{name}", pg_catalog;\n) + source)
        yield name
      ensure
        sql(url, %(DROP SCHEMA "#{name}" CASCADE))
      end
    end

    def fingerprint(url : String, schema : String, *, exclude_ledger : Bool = false) : JSON::Any
      query = CATALOG.gsub(":schema", "'#{schema}'")
      if exclude_ledger
        {"c.relnamespace=", "c.relnamespace =", "t.relnamespace="}.each do |predicate|
          alias_name = predicate.starts_with?("c") ? "c" : "t"
          query = query.gsub(predicate, "#{alias_name}.relname <> 'schema_migrations' AND #{predicate}")
        end
      end
      result = sql(url, %(SET search_path TO "#{schema}", pg_catalog;\n) + query)
      JSON.parse(result.lines.last.gsub(schema + ".", "<schema>."))
    end

    def assert_same(left : JSON::Any, right : JSON::Any, label : String)
      differences = left.as_h.keys.select { |key| left[key] != right[key]? }
      raise ArgumentError.new("#{label}: schema differs in #{differences.join(", ")}") unless differences.empty?
    end

    def verify_existing(url : String, paths : Array(Path))
      replay(url, paths) do |expected|
        assert_same(fingerprint(url, expected), fingerprint(url, "public", exclude_ledger: true), "Cannot adopt checksums for existing migration ledger")
      end
    end

    def check
      url = @database.database_url("test")
      files = @database.migration_files
      pairs = files.map do |version, path|
        rollbacks = Dir.glob((@database.settings.root / @database.settings.rollback_directory / "#{version}_*.sql").to_s)
        raise ArgumentError.new("A reviewed rollback file is required for #{version}") unless rollbacks.size == 1
        {version, path, Path[rollbacks.first]}
      end
      replay(url, [] of Path) do |schema|
        pairs.each do |version, migration, rollback|
          before = fingerprint(url, schema)
          apply_files(url, schema, [migration])
          after = fingerprint(url, schema)
          apply_files(url, schema, [rollback])
          assert_same(before, fingerprint(url, schema), "Rollback #{version}")
          apply_files(url, schema, [migration])
          assert_same(after, fingerprint(url, schema), "Replay #{version}")
        end
      end
      @output.puts "Verified #{pairs.size} migrations with rollback and replay, including indexes and comments."
    end
  end
end

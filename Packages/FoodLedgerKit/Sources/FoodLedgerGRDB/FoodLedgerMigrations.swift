import FoodLedgerApplication
import GRDB

extension FoodLedgerGRDBStore {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_food_ledger") { db in
            try db.execute(sql: "PRAGMA application_id = \(applicationID)")
            try db.execute(sql: "PRAGMA user_version = \(schemaVersion)")
            try db.execute(sql: schemaSQL)
            try db.execute(
                sql: "INSERT INTO ledger_metadata(key, value) VALUES ('schema_identity', 'food-ledger-v1')"
            )
            try installLineageTriggers(db)
            try installImmutableTriggers(db)
        }
        return migrator
    }

    private static let schemaSQL = """
        CREATE TABLE ledger_metadata (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        );
        CREATE TABLE capture_evidence (evidence_id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL);
        CREATE TABLE user_assertion (
            assertion_id TEXT PRIMARY KEY NOT NULL,
            evidence_id TEXT REFERENCES capture_evidence(evidence_id),
            supersedes_id TEXT REFERENCES user_assertion(assertion_id),
            payload BLOB NOT NULL
        );
        CREATE TABLE product (product_id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL);
        CREATE TABLE product_version (
            version_id TEXT PRIMARY KEY NOT NULL,
            product_id TEXT NOT NULL REFERENCES product(product_id),
            ordinal INTEGER NOT NULL CHECK (ordinal > 0),
            supersedes_id TEXT REFERENCES product_version(version_id),
            payload BLOB NOT NULL
        );
        CREATE INDEX product_version_product ON product_version(product_id, ordinal);
        CREATE TABLE product_version_evidence (
            version_id TEXT NOT NULL REFERENCES product_version(version_id),
            position INTEGER NOT NULL CHECK (position >= 0),
            evidence_id TEXT NOT NULL REFERENCES capture_evidence(evidence_id),
            PRIMARY KEY (version_id, position),
            UNIQUE (version_id, evidence_id)
        );
        CREATE TABLE product_version_assertion (
            version_id TEXT NOT NULL REFERENCES product_version(version_id),
            position INTEGER NOT NULL CHECK (position >= 0),
            assertion_id TEXT NOT NULL REFERENCES user_assertion(assertion_id),
            PRIMARY KEY (version_id, position),
            UNIQUE (version_id, assertion_id)
        );
        CREATE TABLE quantity_conversion_version (
            version_id TEXT PRIMARY KEY NOT NULL,
            ordinal INTEGER NOT NULL CHECK (ordinal > 0),
            supersedes_id TEXT REFERENCES quantity_conversion_version(version_id),
            source_release_id TEXT REFERENCES source_release(source_release_id),
            evidence_id TEXT REFERENCES capture_evidence(evidence_id),
            payload BLOB NOT NULL
        );
        CREATE TABLE library_entry (library_entry_id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL);
        CREATE TABLE library_entry_version (
            version_id TEXT PRIMARY KEY NOT NULL,
            library_entry_id TEXT NOT NULL REFERENCES library_entry(library_entry_id),
            product_version_id TEXT NOT NULL REFERENCES product_version(version_id),
            ordinal INTEGER NOT NULL CHECK (ordinal > 0),
            supersedes_id TEXT REFERENCES library_entry_version(version_id),
            quantity_conversion_version_id TEXT REFERENCES quantity_conversion_version(version_id),
            payload BLOB NOT NULL
        );
        CREATE TABLE resolution (
            resolution_id TEXT PRIMARY KEY NOT NULL,
            product_version_id TEXT NOT NULL REFERENCES product_version(version_id),
            payload BLOB NOT NULL
        );
        CREATE TABLE resolution_version (
            version_id TEXT PRIMARY KEY NOT NULL,
            resolution_id TEXT NOT NULL REFERENCES resolution(resolution_id),
            ordinal INTEGER NOT NULL CHECK (ordinal > 0),
            supersedes_id TEXT REFERENCES resolution_version(version_id),
            payload BLOB NOT NULL
        );
        CREATE TABLE resolution_version_source_release (
            version_id TEXT NOT NULL REFERENCES resolution_version(version_id),
            position INTEGER NOT NULL CHECK (position >= 0),
            source_release_id TEXT NOT NULL REFERENCES source_release(source_release_id),
            PRIMARY KEY (version_id, position),
            UNIQUE (version_id, source_release_id)
        );
        CREATE TABLE resolution_version_decision (
            version_id TEXT NOT NULL REFERENCES resolution_version(version_id),
            position INTEGER NOT NULL CHECK (position >= 0),
            decision_id TEXT NOT NULL REFERENCES candidate_decision(decision_id),
            PRIMARY KEY (version_id, position),
            UNIQUE (version_id, decision_id)
        );
        CREATE TABLE resolution_version_assertion (
            version_id TEXT NOT NULL REFERENCES resolution_version(version_id),
            position INTEGER NOT NULL CHECK (position >= 0),
            assertion_id TEXT NOT NULL REFERENCES user_assertion(assertion_id),
            PRIMARY KEY (version_id, position),
            UNIQUE (version_id, assertion_id)
        );
        CREATE TABLE resolution_nutrient (
            resolution_version_id TEXT NOT NULL REFERENCES resolution_version(version_id),
            position INTEGER NOT NULL CHECK (position >= 0 AND position < 39),
            nutrient_key TEXT NOT NULL,
            payload BLOB NOT NULL,
            PRIMARY KEY (resolution_version_id, position),
            UNIQUE (resolution_version_id, nutrient_key)
        );
        CREATE TABLE log_item (log_item_id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL);
        CREATE TABLE log_item_version (
            version_id TEXT PRIMARY KEY NOT NULL,
            log_item_id TEXT NOT NULL REFERENCES log_item(log_item_id),
            product_version_id TEXT REFERENCES product_version(version_id),
            ordinal INTEGER NOT NULL CHECK (ordinal > 0),
            supersedes_id TEXT REFERENCES log_item_version(version_id),
            original_resolution_version_id TEXT NOT NULL REFERENCES resolution_version(version_id),
            effective_resolution_version_id TEXT NOT NULL REFERENCES resolution_version(version_id),
            quantity_conversion_version_id TEXT REFERENCES quantity_conversion_version(version_id),
            payload BLOB NOT NULL
        );
        CREATE TABLE log_item_component (
            version_id TEXT NOT NULL REFERENCES log_item_version(version_id),
            position INTEGER NOT NULL CHECK (position >= 0),
            component_version_id TEXT NOT NULL REFERENCES log_item_version(version_id),
            PRIMARY KEY (version_id, position)
        );
        CREATE TABLE plate (plate_id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL);
        CREATE TABLE plate_weight_version (
            version_id TEXT PRIMARY KEY NOT NULL,
            plate_id TEXT NOT NULL REFERENCES plate(plate_id),
            ordinal INTEGER NOT NULL CHECK (ordinal > 0),
            supersedes_id TEXT REFERENCES plate_weight_version(version_id),
            evidence_id TEXT REFERENCES capture_evidence(evidence_id),
            payload BLOB NOT NULL
        );
        CREATE TABLE candidate_decision (
            decision_id TEXT PRIMARY KEY NOT NULL,
            source_release_id TEXT NOT NULL REFERENCES source_release(source_release_id),
            assertion_id TEXT REFERENCES user_assertion(assertion_id),
            payload BLOB NOT NULL
        );
        CREATE TABLE candidate_decision_evidence (
            decision_id TEXT NOT NULL REFERENCES candidate_decision(decision_id),
            position INTEGER NOT NULL CHECK (position >= 0),
            evidence_id TEXT NOT NULL REFERENCES capture_evidence(evidence_id),
            PRIMARY KEY (decision_id, position),
            UNIQUE (decision_id, evidence_id)
        );
        CREATE TABLE conflict (conflict_id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL);
        CREATE TABLE source_release (source_release_id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL);
        CREATE TABLE source_installation (
            source_release_id TEXT PRIMARY KEY NOT NULL REFERENCES source_release(source_release_id),
            payload BLOB NOT NULL
        );
        CREATE TABLE ledger_actor (
            actor_id TEXT PRIMARY KEY NOT NULL,
            sequence INTEGER NOT NULL CHECK (sequence >= 0),
            operation_hash TEXT NOT NULL
        );
        CREATE TABLE ledger_operation (
            operation_id TEXT PRIMARY KEY NOT NULL,
            actor_id TEXT NOT NULL,
            actor_sequence INTEGER NOT NULL CHECK (actor_sequence > 0),
            operation_type TEXT NOT NULL,
            created_at REAL NOT NULL,
            affected_ids BLOB NOT NULL,
            payload BLOB NOT NULL,
            payload_hash TEXT NOT NULL,
            previous_operation_hash TEXT,
            operation_hash TEXT NOT NULL,
            idempotency_key TEXT,
            UNIQUE(actor_id, actor_sequence),
            UNIQUE(actor_id, operation_hash)
        );
        """

    private static func installImmutableTriggers(_ db: Database) throws {
        let tables = [
            "capture_evidence", "user_assertion", "product", "product_version",
            "product_version_evidence", "product_version_assertion",
            "quantity_conversion_version", "library_entry", "library_entry_version",
            "resolution", "resolution_version", "resolution_version_source_release",
            "resolution_version_decision", "resolution_version_assertion",
            "resolution_nutrient", "log_item", "log_item_version", "log_item_component",
            "plate", "plate_weight_version", "candidate_decision", "candidate_decision_evidence",
            "conflict", "source_release", "source_installation", "ledger_operation"
        ]
        for table in tables {
            try db.execute(sql: """
                CREATE TRIGGER \(table)_immutable_update
                BEFORE UPDATE ON \(table)
                BEGIN SELECT RAISE(ABORT, 'immutable \(table)'); END;
                """)
            try db.execute(sql: """
                CREATE TRIGGER \(table)_immutable_delete
                BEFORE DELETE ON \(table)
                BEGIN SELECT RAISE(ABORT, 'immutable \(table)'); END;
                """)
        }
    }

    private static func installLineageTriggers(_ db: Database) throws {
        let stableChains = [
            ("product_version", "product_id"),
            ("library_entry_version", "library_entry_id"),
            ("resolution_version", "resolution_id"),
            ("log_item_version", "log_item_id"),
            ("plate_weight_version", "plate_id")
        ]
        for (table, stableID) in stableChains {
            try db.execute(sql: """
                CREATE TRIGGER \(table)_lineage
                BEFORE INSERT ON \(table)
                WHEN (
                    NEW.supersedes_id IS NULL AND (
                        NEW.ordinal != 1 OR
                        EXISTS (SELECT 1 FROM \(table) WHERE \(stableID) = NEW.\(stableID))
                    )
                ) OR (
                    NEW.supersedes_id IS NOT NULL AND NOT EXISTS (
                        SELECT 1 FROM \(table)
                        WHERE version_id = NEW.supersedes_id
                          AND \(stableID) = NEW.\(stableID)
                          AND ordinal < NEW.ordinal
                    )
                )
                BEGIN SELECT RAISE(ABORT, 'invalid lineage \(table)'); END;
                """)
        }
        try db.execute(sql: """
            CREATE TRIGGER quantity_conversion_version_lineage
            BEFORE INSERT ON quantity_conversion_version
            WHEN (NEW.supersedes_id IS NULL AND NEW.ordinal != 1)
              OR (NEW.supersedes_id IS NOT NULL AND NOT EXISTS (
                    SELECT 1 FROM quantity_conversion_version
                    WHERE version_id = NEW.supersedes_id AND ordinal < NEW.ordinal
              ))
            BEGIN SELECT RAISE(ABORT, 'invalid lineage quantity_conversion_version'); END;
            """)
    }
}

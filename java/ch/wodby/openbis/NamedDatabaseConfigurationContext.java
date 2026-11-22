package ch.wodby.openbis;

import ch.systemsx.cisd.dbmigration.DatabaseConfigurationContext;

/**
 * A database configuration context with a database name set as a whole.
 *
 * <p>openBIS names a database {@code <basicDatabaseName>_<databaseKind>}. On Wodby the database already exists with a
 * name Wodby chose, so the start script sets that name here. An empty or unresolved name keeps openBIS's own naming.
 */
public class NamedDatabaseConfigurationContext extends DatabaseConfigurationContext {
    private String fixedDatabaseName;

    public void setFixedDatabaseName(String name) {
        if (name == null || name.isBlank() || name.startsWith("${")) {
            fixedDatabaseName = null;
        } else {
            fixedDatabaseName = name.trim();
        }
    }

    @Override
    public String getDatabaseName() {
        if (fixedDatabaseName != null) {
            return fixedDatabaseName;
        }
        return super.getDatabaseName();
    }
}

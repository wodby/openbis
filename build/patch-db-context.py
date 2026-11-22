"""Points openBIS's two application-server database contexts at NamedDatabaseConfigurationContext.

Each context gets fixedDatabaseName from a service property (database.name, messages-database.name), which the start
script sets to the database Wodby created, and loses readOnlyGroup, a role a database owner without superuser rights
cannot create. Fails if the upstream file no longer looks as expected.
"""
import re
import sys

path = sys.argv[1]
xml = open(path).read()
contexts = {
    "db-configuration-context": "${database.name}",
    "messages-db-configuration-context": "${messages-database.name}",
}
for bean_id, name in contexts.items():
    pattern = re.compile(
        r'(<bean id="' + re.escape(bean_id) + r'"\s+class=")ch\.systemsx\.cisd\.dbmigration\.DatabaseConfigurationContext(")([^>]*>)'
    )
    xml, count = pattern.subn(
        r"\1ch.wodby.openbis.NamedDatabaseConfigurationContext\2\3"
        + '\n        <property name="fixedDatabaseName" value="' + name + '" />',
        xml,
    )
    if count != 1:
        sys.exit(f"bean {bean_id} not found in {path}")
xml, count = re.subn(r'\n\s*<property name="readOnlyGroup" value="openbis_readonly" />', "", xml)
if count != 2:
    sys.exit(f"expected 2 readOnlyGroup properties in {path}, found {count}")
open(path, "w").write(xml)

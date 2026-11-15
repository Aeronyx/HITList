import Foundation

/// Brief 137: a small Todoist backup written to the documented columns, for the hosted tests and for the Debug
/// launch argument `-todoistImportFixture` (Settings opens the import's preview on it, since a file picker cannot be
/// driven). Two projects: the Inbox and "Home Base" with a section, sub-tasks, labels, a heading, a repeat, a deadline,
/// a comment and a date HITList cannot read.
enum TodoistFixture {
    static let launchArgument = "-todoistImportFixture"

    static let inbox = """
    TYPE,CONTENT,DESCRIPTION,PRIORITY,INDENT,AUTHOR,RESPONSIBLE,DATE,DATE_LANG,TIMEZONE,DURATION,DURATION_UNIT,DEADLINE,DEADLINE_LANG\r
    task,Call the dentist @phone,,2,1,George (1),,tomorrow,en,,,None,,\r
    task,Read the lease,"Pages 3 to 5, the ""pets"" clause",4,1,George (1),,,,,,None,,\r

    """

    static let homeBase = """
    TYPE,CONTENT,DESCRIPTION,PRIORITY,INDENT,AUTHOR,RESPONSIBLE,DATE,DATE_LANG,TIMEZONE,DURATION,DURATION_UNIT,DEADLINE,DEADLINE_LANG,meta\r
    meta,view_style=list,,,,,,,,,,,,,\r
    task,* Spring cleaning,,4,1,George (1),,,,,,None,,,\r
    task,Water the plants,,4,1,George (1),,every 3 days,en,,,None,,,\r
    note,The fern likes less,,,,George (1),,,,,,,,,\r
    ,,,,,,,,,,,,,,\r
    section,Errands,,,,,,,,,,,,,\r
    task,Groceries @shop,,3,1,George (1),,,,,,None,,,\r
    task,Bread,,4,2,George (1),,,,,,None,,,\r
    task,Sourdough,,4,3,George (1),,,,,,None,,,\r
    task,Eggs,,4,2,George (1),,,,,,None,,,\r
    task,Pick up the dry cleaning,,4,2,George (1),,every fri at 5pm,en,US/Eastern,,None,,,\r
    task,Renew the passport,,1,1,George (1),,when the photos come,en,,30,minute,2027-01-15,en,\r

    """

    static var files: [TodoistFiles.File] {
        [TodoistFiles.File(name: "Inbox [2200000001].csv", data: Data(inbox.utf8)),
         TodoistFiles.File(name: "Home Base [2200000002].csv", data: Data(homeBase.utf8))]
    }

    static var isRequested: Bool {
        #if DEBUG
        CommandLine.arguments.contains(launchArgument)
        #else
        false
        #endif
    }
}

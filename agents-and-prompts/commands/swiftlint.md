# Run Swiftlint and fix related issues

Run swiftlint. For each file with found issues, split the issues into groups of 5. Assign a subtask to resolve each 
group of 5. When all issues for a given file are resolved, assign to a new subtask to check the work. When all work in a 
given file has been checked, commit the changes of that file. Use drews-xcode-mcp to build the project again and make 
sure it builds without errors. If there are new errors, resolved them by fixing the issues you or one of your subtasks 
just created. Once those errors are resolved, check your work again and build again with drews-xcode-mcp. When 
drews-xcode-mcp shows things build successfully, commit those changes. DO NOT PUSH ANY CHANGES. Then run swiftlint again
 and continue with the next file.  Continue until no more swiftlint warnings appear, all build errors have been resolved.
 When all files have been resolved, review all the work from all the commits onc last time (using a subtask), and resolve
 any issues. Re-run drews-xcode-mcp to build again and rerun swiftlint again for good measure.  Repeat until everything 
is resolved.  COMMIT ALL WORK.  DO NOT PUSH


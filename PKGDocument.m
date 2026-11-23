/* All Rights reserved */

#include <AppKit/AppKit.h>
#include "PKGDocument.h"
#include "PKGWindowController.h"

@implementation PKGDocument

- (void) makeWindowControllers
{
  windowController = [[PKGWindowController alloc] initWithWindowNibName: @"PackageWindow"];
  [self addWindowController: windowController];
  RELEASE(windowController);
}

- (BOOL) readFromFile: (NSString *)path ofType: (NSString *)type
{
  BOOL directory = NO;
  return [[NSFileManager defaultManager] fileExistsAtPath: path isDirectory: &directory] && !directory;
}

- (BOOL) isDocumentEdited
{
  return NO;
}

@end

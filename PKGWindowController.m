/* All Rights reserved */

#include <AppKit/AppKit.h>
#include "PKGWindowController.h"

static void
ConfigureLabels(NSView *container, NSString *name)
{
  NSEnumerator *enumerator = [[container subviews] objectEnumerator];
  NSView *child;
  while ((child = [enumerator nextObject]) != nil)
    {
      if ([child isKindOfClass: [NSTextField class]])
        {
          NSTextField *field = (NSTextField *)child;
          if (![field isEditable])
            [field setBordered: NO];
          if ([[field stringValue] isEqual: @"AppName"])
            [field setStringValue: name];
        }
      ConfigureLabels(child, name);
    }
}

@interface PKGWindowController (Private)

- (void) startOperation: (NSDictionary *)request;
- (void) performOperation: (NSDictionary *)request;
- (void) operationFinished: (NSDictionary *)result;
- (void) showFiles: (NSArray *)files title: (NSString *)title;

@end

@implementation PKGWindowController

- (void) dealloc
{
  RELEASE(infoView);
  RELEASE(logView);
  RELEASE(progressView);
  RELEASE(packageInfo);
  RELEASE(installedFiles);
  DEALLOC;
}

- (void) windowDidLoad
{
  NSScrollView *scroll;
  NSArray *receipts;
  [super windowDidLoad];
  infoView = RETAIN([infoWindow contentView]);
  logView = RETAIN([logWindow contentView]);
  progressView = RETAIN([progressWindow contentView]);
  /* Keep the Gorm window, controls, and connections; give its List pane a
     consistently configured text view for archive paths and receipts. */
  scroll = AUTORELEASE([[NSScrollView alloc] initWithFrame: [[view contentView] bounds]]);
  [scroll setHasVerticalScroller: YES];
  [scroll setHasHorizontalScroller: YES];
  [scroll setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  fileText = AUTORELEASE([[NSTextView alloc] initWithFrame: [scroll bounds]]);
  [fileText setEditable: NO];
  [fileText setFont: [NSFont userFixedPitchFontOfSize: 12]];
  [fileText setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  [scroll setDocumentView: fileText];
  RELEASE(logView);
  logView = RETAIN(scroll);
  [deleteButton setTitle: @"Installed"];
  [deleteButton setToolTip: @"Show files from the last successful installation"];
  [listButton setTitle: @"Archive"];
  [listButton setToolTip: @"List all entries in the archive"];
  {
    NSArray *fields = [NSArray arrayWithObjects: location, size, versionNumber, status, nil];
    NSEnumerator *enumerator = [fields objectEnumerator];
    NSView *field;
    while ((field = [enumerator nextObject]) != nil)
      {
        NSRect frame = [field frame];
        frame.size.width = [infoView bounds].size.width - frame.origin.x - 20;
        [field setFrame: frame];
        [field setAutoresizingMask: NSViewWidthSizable];
      }
    [[description enclosingScrollView] setFrame: NSMakeRect(105, 22, [infoView bounds].size.width - 125, 170)];
    [description setEditable: NO];
  }
  ConfigureLabels(infoView, [[self document] displayName]);
  [location setEditable: YES];
  [location setBordered: YES];
  [location setBezeled: YES];
  [location setDrawsBackground: YES];
  [location setStringValue: [NSHomeDirectory() stringByAppendingPathComponent: @"Applications"]];
  [status setBordered: NO];
  [size setBordered: NO];
  [versionNumber setBordered: NO];
  [opStatus setBordered: NO];
  receipts = [[[NSUserDefaults standardUserDefaults] dictionaryForKey: @"InstallationReceipts"] objectForKey: [[self document] fileName]];
  ASSIGN(installedFiles, receipts);
  [self startOperation: [NSDictionary dictionaryWithObject: @"inspect" forKey: @"operation"]];
}

- (void) changeView: (id)sender
{
  NSInteger tag = [[sender selectedItem] tag];
  id content = tag == 0 ? infoView : tag == 1 ? logView : progressView;
  if (content != nil)
    [view setContentView: content];
}

- (void) showFiles: (NSArray *)files title: (NSString *)title
{
  [fileText setString: [NSString stringWithFormat: @"%@\n\n%@", title,
    [files count] ? [files componentsJoinedByString: @"\n"] : @"No files recorded."]];
  [view setContentView: logView];
  [viewPulldown selectItemWithTag: 1];
}

- (void) deletePackage: (id)sender
{
  [self showFiles: installedFiles title: @"Files from the last successful installation"];
}

- (void) listPackage: (id)sender
{
  [self showFiles: [packageInfo objectForKey: @"files"] title: @"All archive entries"];
}

- (void) installPackage: (id)sender
{
  NSString *format = [packageInfo objectForKey: @"format"];
  NSString *destination = [[location stringValue] stringByExpandingTildeInPath];
  BOOL native = [format isEqual: @"deb"] || [format isEqual: @"rpm"];
  NSInteger answer;
  if (busy || packageInfo == nil)
    return;
  if (native)
    destination = @"/";
  else if (![destination isAbsolutePath])
    {
      NSRunAlertPanel(@"Installation destination", @"Enter an absolute directory path in Location.", @"OK", nil, nil);
      return;
    }
  answer = NSRunAlertPanel(@"Install package", @"Install %@ into %@? Install only packages you trust. System packages can run installation scripts as root.",
    native ? @"Authenticate and Install" : @"Install", @"Cancel", native ? nil : @"Install as Root",
    [[self document] displayName], destination);
  if (answer == NSAlertAlternateReturn)
    return;
  if (!native && answer == NSAlertDefaultReturn)
    {
      NSError *error = nil;
      if (![[NSFileManager defaultManager] createDirectoryAtPath: destination withIntermediateDirectories: YES attributes: nil error: &error])
        {
          NSRunAlertPanel(@"Cannot create destination", @"%@", @"OK", nil, nil, [error localizedDescription]);
          return;
        }
    }
  [self startOperation: [NSDictionary dictionaryWithObjectsAndKeys:
    @"install", @"operation", destination, @"destination",
    [NSNumber numberWithBool: native || answer == NSAlertOtherReturn], @"root", nil]];
}

- (void) startOperation: (NSDictionary *)request
{
  NSMutableDictionary *job = [NSMutableDictionary dictionaryWithDictionary: request];
  [job setObject: [[self document] fileName] forKey: @"path"];
  busy = YES;
  [installButton setEnabled: NO];
  [listButton setEnabled: NO];
  [deleteButton setEnabled: NO];
  [status setStringValue: @"Working…"];
  [opStatus setStringValue: @"Working… Authentication may be required."];
  [progress setIndeterminate: YES];
  [progress startAnimation: self];
  [NSThread detachNewThreadSelector: @selector(performOperation:) toTarget: self withObject: job];
}

- (void) performOperation: (NSDictionary *)request
{
  CREATE_AUTORELEASE_POOL(pool);
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  NSTask *task = AUTORELEASE([[NSTask alloc] init]);
  NSPipe *output = [NSPipe pipe];
  NSMutableArray *arguments = [NSMutableArray array];
  NSString *helper = [[NSBundle mainBundle] pathForResource: @"installer_backend" ofType: @"py"];
  @try
    {
      NSData *data;
      NSDictionary *response;
      NSString *parseError = nil;
      if ([[request objectForKey: @"root"] boolValue])
        {
          [task setLaunchPath: @"/usr/bin/pkexec"];
          [arguments addObject: @"/usr/bin/python3"];
        }
      else
        [task setLaunchPath: @"/usr/bin/python3"];
      [arguments addObjectsFromArray: [NSArray arrayWithObjects: @"-I", helper,
        [request objectForKey: @"operation"], [request objectForKey: @"path"], nil]];
      if ([request objectForKey: @"destination"])
        [arguments addObjectsFromArray: [NSArray arrayWithObjects: @"--destination", [request objectForKey: @"destination"], nil]];
      [task setArguments: arguments];
      [task setStandardOutput: output];
      [task setStandardError: output];
      [task launch];
      data = [[output fileHandleForReading] readDataToEndOfFile];
      [task waitUntilExit];
      response = [NSPropertyListSerialization propertyListFromData: data mutabilityOption: NSPropertyListImmutable format: NULL errorDescription: &parseError];
      if ([response isKindOfClass: [NSDictionary class]])
        [result addEntriesFromDictionary: response];
      else
        {
          NSString *message = AUTORELEASE([[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding]);
          [result setObject: [NSString stringWithFormat: @"Authentication or installer failed (exit %d). %@", [task terminationStatus], message ? message : @""] forKey: @"error"];
        }
      RELEASE(parseError);
    }
  @catch (NSException *exception)
    {
      [result setObject: [exception reason] forKey: @"error"];
    }
  [result setObject: [request objectForKey: @"operation"] forKey: @"operation"];
  [self performSelectorOnMainThread: @selector(operationFinished:) withObject: result waitUntilDone: YES];
  RELEASE(pool);
}

- (void) operationFinished: (NSDictionary *)result
{
  BOOL success = [[result objectForKey: @"ok"] boolValue];
  busy = NO;
  [progress stopAnimation: self];
  [status setStringValue: success ? @"Ready" : @"Failed"];
  [opStatus setStringValue: success ? @"Complete" : @"Operation failed"];
  if (!success)
    NSRunAlertPanel(@"Installer", @"%@", @"OK", nil, nil, [result objectForKey: @"error"]);
  else if ([[result objectForKey: @"operation"] isEqual: @"inspect"])
    {
      ASSIGN(packageInfo, result);
      [description setString: [NSString stringWithFormat: @"%@\n\nChoose a destination in Location, then click Install. Archive installs create a new folder there. DEB and RPM packages use the system package manager.", [result objectForKey: @"name"]]];
      if ([[result objectForKey: @"format"] isEqual: @"deb"] || [[result objectForKey: @"format"] isEqual: @"rpm"])
        {
          [location setStringValue: @"/"];
          [location setEditable: NO];
          [location setBordered: NO];
          [location setBezeled: NO];
        }
      [versionNumber setStringValue: [result objectForKey: @"version"]];
      [size setStringValue: [NSString stringWithFormat: @"%@ bytes", [result objectForKey: @"size"]]];
      [status setStringValue: [NSString stringWithFormat: @"%@ — %lu entries", [result objectForKey: @"format"], (unsigned long)[[result objectForKey: @"files"] count]]];
      [self listPackage: self];
    }
  else
    {
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
      NSMutableDictionary *receipts = [NSMutableDictionary dictionaryWithDictionary: [defaults dictionaryForKey: @"InstallationReceipts"] ?: [NSDictionary dictionary]];
      ASSIGN(installedFiles, [result objectForKey: @"files"]);
      [receipts setObject: installedFiles forKey: [[self document] fileName]];
      [defaults setObject: receipts forKey: @"InstallationReceipts"];
      [defaults synchronize];
      [status setStringValue: @"Installed"];
      [self deletePackage: self];
    }
  [installButton setEnabled: packageInfo != nil];
  [listButton setEnabled: packageInfo != nil];
  [deleteButton setEnabled: installedFiles != nil];
}

@end

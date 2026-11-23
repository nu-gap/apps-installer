/* All Rights reserved */

#include <AppKit/AppKit.h>

@interface PKGWindowController : NSWindowController
{
  id deleteButton;
  id description;
  id iconView;
  id installButton;
  id listButton;
  id listView;
  id location;
  id opStatus;
  id progress;
  id size;
  id status;
  id versionNumber;
  id view;
  id viewPulldown;
  id logWindow;
  id infoWindow;
  id progressWindow;
  id logView;
  id infoView;
  id progressView;
  BOOL busy;
  NSDictionary *packageInfo;
  NSArray *installedFiles;
  NSTextView *fileText;
}

- (void) changeView: (id)sender;
- (void) deletePackage: (id)sender;
- (void) installPackage: (id)sender;
- (void) listPackage: (id)sender;

@end

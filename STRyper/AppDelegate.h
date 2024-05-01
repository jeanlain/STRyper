//
//  AppDelegate.h
//  STRyper
//
//  Created by Jean Peccoud on 11/08/2014.
//  Copyright (c) 2014 Jean Peccoud. All rights reserved.


//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.


@import Cocoa;

#import "NSError+NSErrorAdditions.h"
#import "CDUndoManager.h"

/// The delegate of the application.
///
/// This class serves as delegate of the application. It manages the core data stack (including saving).
/// It also manages the application preferences/settings (user defaults and settings window),
/// and records the ``SourceListController/selectedFolder`` objects when the app quits, so it can be selected at the next launch.
@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSControlTextEditingDelegate> {
		
}

/// The persistent container of the core data database used by the application.
///
/// If the persistent store cannot be loaded, the method shows an alert that proposes to create a new one and copy the old one, or to quit.
@property (readonly, strong) NSPersistentContainer *persistentContainer;

/// Returns the ``persistentContainer``'s view context.
///
/// This context is the one use by most methods of this application. It has an undo manager that is used by the main window.
@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;

/// A context that is a child of ``managedObjectContext`` and has no undo manager .
///
/// The same context is returned at each call.
@property (readonly, strong, nonatomic) NSManagedObjectContext *childContext;

/// Returns a new managed objet context that is a child of ``managedObjectContext`` and which uses a private queue.
@property (readonly, strong, nonatomic) NSManagedObjectContext *newChildContext;

/// Returns a new managed object context that is a child of ``managedObjectContext``, and which uses the main queue.
@property (readonly, strong, nonatomic) NSManagedObjectContext *newChildContextOnMainQueue;

/// Saves the ``managedObjectContext``, if it has changes.
///
/// If saving fails, the method tries to recover from validation errors by calling ``recoverFromErrorInContext:showLog:``.
/// - Parameter sender: The sender of the message (ignored by the method).
- (IBAction)saveAction:(id)sender;


/// Tries to recover from an error that prevented saving a context, by undoing recent changes and trying to save the context.
///
/// This methods sends `-rollback` to the context if saving fails after undoing or if undoing is not possible.
///
/// The method then shows an alert with an optimal button that can be clicked to open the log window (see ``MainWindowController/errorLogWindow``).
/// The log window will contain the description of the error(s) that prevented saving.
/// - Parameters:
///   - context: The managed object context for which validation errors should be recovered.
///   This should preferably be the "view" context. This method has not been tested with a child context or a context using a background queue.
///   - showLog: Whether the alert should have a button allowing to open the log window. See discussion.
+(void)recoverFromErrorInContext:(NSManagedObjectContext *) context showLog:(BOOL)showLog;

/// Shows the application help.
/// - Parameter sender: The object that sent the message. It is ignored by the method.
- (IBAction)showHelp:(id)sender;


/// Keys of the user defaults. See their default value in the implementation.
typedef NSString *const UserDefaultKey;

/// Whether saturated regions should be shown in the views
extern UserDefaultKey ShowOffScale,

/// Debugging peaks (to remove on release)
OutlinePeaks,

/// Whether trace views should show tooltip describing hovered peaks.
ShowPeakTooltips,

/// The start size (float) of the default visible range of trace views.
DefaultStartSize,

/// The end size (float) of the default visible range of trace views.
DefaultEndSize,

/// The synchronized start size of trace views
ReferenceStartSize,

/// The synchronized end size of trace views
ReferenceEndSize,

/// The number of trace views to show in the detailed view (see ``DetailedViewController/numberOfRowsPerWindow``).
TraceRowsPerWindow,

/// An integer describing how traces are stacked in trace views (see ``DetailedViewController/stackMode``).
TraceStackMode,

/// An integer describing how the vertical scales of trace views are managed (see ``DetailedViewController/topFluoMode``).
TraceTopFluoMode,

/// Whether peaks resulting from crosstalk should be painted with the colors of the channel that induce crosstalk.
PaintCrosstalkPeaks,

/// Whether peaks resulting from crosstalk should be ignored when trace views adjust their vertical scales to highest visible peaks.
IgnoreCrosstalkPeaks,

/// Whether the horizontal positions and scales of trace views should be synchronized.
SynchronizeViews,

/// Whether a scroll gesture on the top ruler allows moving between markers
SwipeBetweenMarkers,

/// Whether trace views plot raw fluorescence data (see ``TraceView/showRawData``.
ShowRawData,

/// Whether trace views use fluorescence data with peak heights maintained when they do not plot raw data (see ``TraceView/maintainPeakHeights``).
MaintainPeakHeights,

/// Whether trace views show disabled bins (see ``TraceView/showDisabledBins``).
ShowBins,

/// Whether trace views show data from the first channel (see ``Trace/channel``).
ShowChannel0,

/// Whether trace views show data from the second channel (see ``Trace/channel``).
ShowChannel1,

/// Whether trace views show data from the third channel (see ``Trace/channel``).
ShowChannel2,

/// Whether trace views show data from the forth channel (see ``Trace/channel``).
ShowChannel3,

/// Whether trace views show data from the fifth channel (see ``Trace/channel``).
ShowChannel4,

/// Whether the metadata of chromatograms should be added to genotype data when genotypes are exported to a text file.
AddSampleInfo,


AutoDetectSizeStandard,

/// The  name (string) given to alleles that are out of bins.
DubiousAlleleName,

/// The name (string) given to missing alleles (those that have a scan of 0).
MissingAlleleName,

/// Whether additional peaks should be annotated during genotyping.
AnnotateAdditionalPeaks,

/// The default polynomial order used for sizing (see ``Chromatogram/polynomialOrder``).
DefaultSizingOrder,

/// The index of the tab that is shown in the bottom pane, which contains an `NSTabView`.
BottomTab,

/// Whether sample search (see ``SampleSearchHelper``) should be case sensitive.
CaseSensitiveSampleSearch;


																																																										
@end

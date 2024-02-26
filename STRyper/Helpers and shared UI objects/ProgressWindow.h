//
//  ProgressWindow.h
//  STRyper
//
//  Created by Jean Peccoud on 27/11/2022.
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


@import  Cocoa;

NS_ASSUME_NONNULL_BEGIN

/// A simple window to show the progress of a background operation.
///
/// The window shows a progress bar, a textfield and a cancel button, and is loaded from a nib file.
@interface ProgressWindow : NSWindow


/// The progress object used to monitor the progress.
///
/// This property is set with ``showProgressWindowForProgress:afterDelay:modal:parentWindow:``
/// and is observed for the `cancelled`, `cancellable`,  `competedUnitCount` and `localizedDescription` keys.
/// These keys are used to update the ``progressBar`` and the ``operationTextField`` of the window.
@property (weak, nonatomic, readonly, nullable) NSProgress *progress;


/// The progress indicator that reports the progress.
///
/// This progress indicator is designed as a progress bar.
/// Changing its `style` to the spinning wheel results in a lot of empty space in the window.
@property (weak, nonatomic, readonly) NSProgressIndicator *progressBar;
														
/// The text field that describes the current operation/progress.
///
/// This text field indicates  "Processing..." by default.
@property (weak, nonatomic, readonly) NSTextField *operationTextField;


/// A button that the user can click to cancel the progress.
///
/// This button is disabled if the progress is not cancellable.
/// It is activated by the escape key and calls ``stopShowingProgressAndClose``.
@property (weak, nonatomic, readonly) NSButton *stopButton;

		
/// Shows the progress window after some delay.
///
/// A delay can be specified to avoid showing the progress window for operations that turn out to be very short.
///
/// The progress indicator is updated by monitoring the progress' `completedUnitCount`, and the ``operationTextField`` shows the progress' `localizedDescription`.
///
/// If the progress is cancelled, the progress window calls ``stopShowingProgressAndClose`` on itself.
/// - Parameters:
///   - progress: The progress to be monitored by the receiver. If it is nil, the ``progressBar`` is set to indeterminate.
///   - delay: The delay after which the progress window should show.
///   - modal: If YES, the progress window is shown as a modal sheet attached to `window`, otherwise it shows as a separate window centered over the `window`
///   - window: The window relative to which the progress window should show.
-(void)showProgressWindowForProgress:(nullable NSProgress *)progress afterDelay:(NSTimeInterval)delay modal:(BOOL)modal parentWindow:(NSWindow *)window;

/// Stops monitoring the progress (nullifies the ``progress`` property ) and closes the window if necessary.
///
/// Calling this method prevents the window from showing after ``showProgressWindowForProgress:afterDelay:modal:parentWindow:``
/// has been called, if the progress window is not shown yet.
-(void)stopShowingProgressAndClose;

@end

NS_ASSUME_NONNULL_END

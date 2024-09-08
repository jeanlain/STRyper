//
//  NewMarkerPopover.h
//  STRyper
//
//  Created by Jean Peccoud on 23/04/2023.
//
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


#import <Cocoa/Cocoa.h>
#import "Mmarker.h"
@class Panel;

NS_ASSUME_NONNULL_BEGIN

/// A popover that lets the user specify attributes for a new molecular marker.
///
/// A NewMarkerPopover comes with a content view having the necessary controls to specify a new molecular marker (``Mmarker`` class).
/// For convenience, this class has properties that allow setting and retrieving the attributes of the marker to create, without the need to access the text fields, and controls.
///
/// This popover has a special behaviour that allows it to be modal, i.e., it prevents events from occurring outside its window when it is shown.
/// In this case, it will not close when an action occurs outside its window except if its `delegate` returns `YES` to `-popoverShouldClose`.
///
/// This behaviour can help to prevent inconsistence from happening while the marker is being created (deleting its panel, modifying other markers of the panel, etc.)
@interface NewMarkerPopover : NSPopover <NSPopoverDelegate, NSControlTextEditingDelegate>

/// Returns a new instance, which is loaded from a nib file.
+(nullable instancetype) popover;

/// The text field specifying the ``Region/start`` coordinate of the marker.
@property (readonly, weak, nonatomic) NSTextField *markerStartTextField;

/// The text field specifying the ``Region/end`` coordinate of the marker.
@property (readonly, weak, nonatomic) NSTextField *markerEndTextField;

/// The text field specifying the ``Region/name`` of the marker.
@property (readonly, weak, nonatomic) NSTextField *markerNameTextField;

/// A popup button for the  ``Mmarker/channel`` of the marker.
@property (readonly, weak, nonatomic) NSPopUpButton *markerChannelPopupButton;

/// The ``Region/start`` coordinate of the new marker.
@property (nonatomic) float markerStart;

/// The ``Region/end`` coordinate of the new marker.
@property (nonatomic) float markerEnd;

/// The ``Region/name``  of the new marker.
@property (nonatomic) NSString *markerName;

/// The  ``Mmarker/channel`` of the new marker.
@property (nonatomic) ChannelNumber markerChannel;

/// Whether the marker is diploid (if the ``Mmarker/ploidy`` equals 2).
@property (nonatomic) BOOL diploid;

/// The length of the repeat motive of the marker, in base pairs), constrained to {2...7}.
@property (nonatomic) NSUInteger motiveLength;

/// The action of the "Add marker" button.
///
/// This property is nil by default.
@property (nonatomic) SEL okAction;

/// The action of the "Cancel" button.
///
/// The default action closes the popover.
@property (nonatomic) SEL cancelAction;

/// The target of the "Add marker" button.
@property (weak, nonatomic) id okActionTarget;

/// The target of the "Cancel" button.
///
/// The default is the popover itself.
@property (weak, nonatomic) id cancelActionTarget;

/// Does the same as `showRelativeToRect:ofView:preferredEdge:` of `NSPopover`, with an option to start a modal session with the popover.
///
/// When `modal` is `YES`, the popover blocks any event outside its window. It must be closed for the modal session to end.
/// - Parameters:
///   - positioningRect: The rectangle within positioningView relative to which the popover should be positioned. Normally set to the bounds of positioningView. May be an empty rectangle, which will default to the bounds of positioningView.
///   - positioningView: The view relative to which the popover should be positioned. Causes the method to raise `NSInvalidArgumentException` if nil.
///   - preferredEdge: The edge of positioningView the popover should prefer to be anchored to.
///   - modal: Whether the popover should be modal.
- (void)showRelativeToRect:(NSRect)positioningRect ofView:(NSView *)positioningView preferredEdge:(NSRectEdge)preferredEdge modal:(BOOL)modal;

@end

NS_ASSUME_NONNULL_END

//
//  NewMarkerPopover.m
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


#import "NewMarkerPopover.h"

@implementation NewMarkerPopover {
	
	BOOL modalState; /// determine it we should start/end a modal session.
	__weak IBOutlet NSTextField *markerStartTextField;
	__weak IBOutlet NSTextField *markerEndTextField;
	__weak IBOutlet NSTextField *markerNameTextField;
	__weak IBOutlet NSSegmentedControl *ploidyControl;
	__weak IBOutlet NSPopUpButton *markerChannelPopupButton;

	__weak IBOutlet NSButton *addMarkerButton;
	__weak IBOutlet NSButton *cancelButton;
	
	__weak id theDelegate;

}


- (instancetype)init {
	self = [super init];
	if(self && [NSBundle.mainBundle loadNibNamed:@"NewMarkerPopover" owner:self topLevelObjects:nil]) {
		self.behavior = NSPopoverBehaviorSemitransient;
		self.cancelAction = @selector(close);
		self.cancelActionTarget = self;
	}
	return self;
}


+ (nullable instancetype)popover {
	return self.new;
}


- (void)showRelativeToRect:(NSRect)positioningRect ofView:(NSView *)positioningView preferredEdge:(NSRectEdge)preferredEdge modal:(BOOL)modal {
	[super showRelativeToRect:positioningRect ofView:positioningView preferredEdge:preferredEdge];
	modalState = modal;
	if(modal) {
		/// When modal, we *must* end the modal session when we close
		/// I have not found another way than responding to -popoverDidClose, which is a delegate method
		/// (No NSWindowDelegate method is called when we close).
		super.delegate = self;
	}
}



- (void)setDelegate:(id<NSPopoverDelegate>)delegate {
	super.delegate = self;

	/// If we are the delegate of ourself, we must allow another object to be our delegate
	/// So we override this to allow two delegates: us (the actual delegate) and the other object
	/// We forward delegate messages we receive to this object.
	if(delegate != self) {
		theDelegate = delegate;
	}
}



- (id<NSPopoverDelegate>)delegate {
	return theDelegate;
}



- (NSPopUpButton *)markerChannelPopupButton {
	return markerChannelPopupButton;
}


- (NSTextField *)markerStartTextField {
	return markerStartTextField;
}


- (float)markerStart {
	return markerStartTextField.floatValue;
}


- (void)setMarkerStart:(float)markerStart {
	markerStartTextField.floatValue = markerStart;
}


- (NSTextField *)markerEndTextField {
	return markerEndTextField;
}


- (float)markerEnd {
	return markerEndTextField.floatValue;
}


- (void)setMarkerEnd:(float)markerEnd {
	markerEndTextField.floatValue = markerEnd;
}


- (NSTextField *)markerNameTextField {
	return markerNameTextField;
}


- (NSString *)markerName {
	return markerNameTextField.stringValue;
}


- (void)setMarkerName:(NSString *)markerName {
	markerNameTextField.stringValue = markerName;
}


- (ChannelNumber)markerChannel {
	return markerChannelPopupButton.indexOfSelectedItem;
}


- (void)setMarkerChannel:(ChannelNumber)markerChannel {
	if(markerChannel >= 0 && markerChannel <= orangeChannelNumber) {
		[markerChannelPopupButton selectItemAtIndex:markerChannel];
	}
}


- (BOOL)diploid {
	return ploidyControl.selectedSegment == 1;
}


- (void)setDiploid:(BOOL)diploid {
	ploidyControl.selectedSegment = diploid ;
}


- (id)okActionTarget {
	return addMarkerButton.target;
}


- (void)setOkActionTarget:(id)target {
	addMarkerButton.target = target;
}


- (void)setOkAction:(SEL)action {
	addMarkerButton.action = action;
}


- (SEL)okAction {
	return addMarkerButton.action;
}


- (void)setCancelActionTarget:(id)target {
	cancelButton.target = target;
}


- (void)setCancelAction:(SEL)action {
	cancelButton.action = action;
}


- (SEL)cancelAction {
	return cancelButton.action;
}


- (void)cancelOperation:(id)sender {
	/// using the escape key equivalent for a button on a popover doesn't work. It seems appkit reserves it for this method.
	if(cancelButton.action) {
		[cancelButton performClick:sender];
	}
	else [self close];
}



- (NSUndoManager *)undoManager {
	/// we prevent undoing when this popover shows, to avoid actions that may affect the validity of adding a marker
	if(modalState) {
		return nil;
	}
	return [super undoManager];
}

/**Delegate method we must override to forward message to our delegate**/

- (BOOL)popoverShouldClose:(NSPopover *)popover {
	if(modalState) {
		return NO;
	}
	if([theDelegate respondsToSelector:@selector(popoverShouldClose:)] && theDelegate != self)  {
		return [theDelegate popoverShouldClose:popover];
	}
	return YES;
}



- (void)popoverWillClose:(NSNotification *)notification {
	if([theDelegate respondsToSelector:@selector(popoverWillClose:)] && theDelegate != self)  {
		[theDelegate popoverWillClose:notification];
	}
}



- (void)popoverDidClose:(NSNotification *)notification {
	if(modalState && notification.object == self) {
		/// This is the only reason why we have to override all these method that allow us to be our own delegate:
		/// to make sure that we exit the modal session when we close.
		/// Otherwise, the app will remained blocked.
		[NSApp stopModal];
		modalState = NO;
	}
	
	if([theDelegate respondsToSelector:@selector(popoverDidClose:)] && theDelegate != self)  {
		[theDelegate popoverDidClose:notification];
	}
}


- (void)popoverWillShow:(NSNotification *)notification {
	if([theDelegate respondsToSelector:@selector(popoverDidClose:)] && theDelegate != self)  {
		[theDelegate popoverWillShow:notification];
	}
}


- (void)popoverDidShow:(NSNotification *)notification {
	if(notification.object == self && modalState) {
		[NSApp runModalForWindow:self.contentViewController.view.window];
	}
	if([theDelegate respondsToSelector:@selector(popoverDidShow:)] && theDelegate != self)  {
		[theDelegate popoverDidShow:notification];
	}
}


- (NSWindow *)detachableWindowForPopover:(NSPopover *)popover {
	if([theDelegate respondsToSelector:@selector(detachableWindowForPopover:)] && theDelegate != self)  {
		return [theDelegate detachableWindowForPopover:popover];
	}
	return nil;
}


- (BOOL)popoverShouldDetach:(NSPopover *)popover {
	if([theDelegate respondsToSelector:@selector(popoverShouldDetach:)] && theDelegate != self)  {
		return [theDelegate popoverShouldDetach:popover];
	}
	return NO;
}



- (void)popoverDidDetach:(NSPopover *)popover {
	if([theDelegate respondsToSelector:@selector(popoverDidDetach:)] && theDelegate != self)  {
		[theDelegate popoverDidDetach:popover];
	}
}


@end

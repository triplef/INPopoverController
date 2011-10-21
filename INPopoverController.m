//
//  INPopoverController.m
//  Copyright 2011 Indragie Karunaratne. All rights reserved.
//
//  Licensed under the BSD License <http://www.opensource.org/licenses/bsd-license>
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import "INPopoverController.h"
#import "INPopoverWindow.h"
#import "INPopoverWindowFrame.h"
#import "INPopoverParentWindow.h"

#include <QuartzCore/QuartzCore.h>

@interface INPopoverController ()
- (void)_setInitialPropertyValues;
- (void)_closePopoverAndResetVariables;
- (void)_callDelegateMethod:(SEL)selector;
- (void)_positionViewFrameChanged:(NSNotification*)notification;
- (void)_setPositionView:(NSView*)newPositionView;
- (void)_setArrowDirection:(INPopoverArrowDirection)direction;
- (void)_setArrowPosition:(CGFloat)position;
- (INPopoverArrowDirection)_arrowDirectionWithPreferredArrowDirection:(INPopoverArrowDirection)direction arrowPosition:(CGFloat *)outArrowPosition;
@property (readonly) NSView *contentView;
@end

@implementation INPopoverController
@synthesize delegate = _delegate;
@synthesize closesWhenPopoverResignsKey = _closesWhenPopoverResignsKey;
@synthesize closesWhenApplicationBecomesInactive = _closesWhenApplicationBecomesInactive;
@synthesize animates = _animates;

#pragma mark -
#pragma mark Initialization

- (id)init
{
	if ((self = [super init])) {
		[self _setInitialPropertyValues];
	}
	return self;
}

- (void)awakeFromNib
{
	[super awakeFromNib];
	[self _setInitialPropertyValues];
}

#pragma mark -
#pragma mark Public Methods

- (id)initWithContentViewController:(NSViewController*)viewController
{
	if ((self = [super init])) {
		[self _setInitialPropertyValues];
		self.contentViewController = viewController;
	}
	return self;
}

- (void)presentPopoverFromRect:(NSRect)rect inView:(NSView*)positionView preferredArrowDirection:(INPopoverArrowDirection)direction anchorsToPositionView:(BOOL)anchors
{
	if (self.popoverIsVisible) { return; } // If it's already visible, do nothing
	NSWindow *mainWindow = [positionView window];
	[self _setPositionView:positionView];
	_viewRect = rect;
	_screenRect = [positionView convertRect:rect toView:nil]; // Convert the rect to window coordinates
	_screenRect.origin = [mainWindow convertBaseToScreen:_screenRect.origin]; // Convert window coordinates to screen coordinates
	CGFloat arrowPosition;
	INPopoverArrowDirection calculatedDirection = [self _arrowDirectionWithPreferredArrowDirection:direction arrowPosition:&arrowPosition]; // Calculate the best arrow direction
	[self _setArrowDirection:calculatedDirection]; // Change the arrow direction of the popover
	[self _setArrowPosition:arrowPosition];
	NSRect windowFrame = [self popoverFrameWithSize:self.contentSize andArrowDirection:calculatedDirection andArrowPosition:arrowPosition]; // Calculate the window frame based on the arrow direction
	[_popoverWindow setFrame:windowFrame display:YES]; // Se the frame of the window
	[[_popoverWindow animationForKey:@"alphaValue"] setDelegate:self];
	
	// Show the popover
	[self _callDelegateMethod:@selector(popoverWillShow:)]; // Call the delegate
	if (self.animates)
	{
		// Animate the popover in
		[_popoverWindow setAlphaValue:1.0];
		[_popoverWindow presentWithPopoverController:self];
	}
	else
	{
		[mainWindow addChildWindow:_popoverWindow ordered:NSWindowAbove]; // Add the popover as a child window of the main window
		[_popoverWindow makeKeyAndOrderFront:nil]; // Show the popover
		[self _callDelegateMethod:@selector(popoverDidShow:)]; // Call the delegate
	}
	
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	if (anchors) {  // If the anchors option is enabled, register for frame change notifications
		[nc addObserver:self selector:@selector(_positionViewFrameChanged:) name:NSViewFrameDidChangeNotification object:self.positionView];
	}
	// When -closesWhenPopoverResignsKey is set to YES, the popover will automatically close when the popover loses its key status
	if (self.closesWhenPopoverResignsKey) {
		[nc addObserver:self selector:@selector(closePopover:) name:NSWindowDidResignKeyNotification object:_popoverWindow];
		if (!self.closesWhenApplicationBecomesInactive)
			[nc addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:nil];
	} else if (self.closesWhenApplicationBecomesInactive) {
		// this is only needed if closesWhenPopoverResignsKey is NO, otherwise we already get a "resign key" notification when resigning active
		[nc addObserver:self selector:@selector(closePopover:) name:NSApplicationDidResignActiveNotification object:nil];
	}
}

- (void)recalculateAndResetArrowDirection
{
	CGFloat arrowPosition;
	INPopoverArrowDirection direction = [self _arrowDirectionWithPreferredArrowDirection:self.arrowDirection arrowPosition:&arrowPosition];
	[self _setArrowDirection:direction];
	[self _setArrowPosition:arrowPosition];
}

- (IBAction)closePopover:(id)sender
{
	if (![_popoverWindow isVisible]) { return; }
	if ([sender isKindOfClass:[NSNotification class]] && [[sender name] isEqualToString:NSWindowDidResignKeyNotification]) {
		// ignore "resign key" notification sent when app becomes inactive unless closesWhenApplicationBecomesInactive is enabled
		if (!self.closesWhenApplicationBecomesInactive && ![NSApp isActive])
			return;
	}
	BOOL close = YES;
	// Check to see if the delegate has implemented the -popoverShouldClose: method
	if ([self.delegate respondsToSelector:@selector(popoverShouldClose:)]) {
		close = [self.delegate popoverShouldClose:self]; 
	}
	if (close) { [self forceClosePopover:nil]; }
}

- (IBAction)forceClosePopover:(id)sender
{
	if (![_popoverWindow isVisible]) { return; }
	[self _callDelegateMethod:@selector(popoverWillClose:)]; // Call delegate
	if (self.animates) {
		[_popoverWindow dismissAnimated];
	} else {
		[self _closePopoverAndResetVariables];
	}
}

// Calculate the frame of the window depending on the arrow direction
- (NSRect)popoverFrameWithSize:(NSSize)contentSize andArrowDirection:(INPopoverArrowDirection)direction andArrowPosition:(CGFloat)arrowPosition
{
	NSRect contentRect = NSZeroRect;
	contentRect.size = contentSize;
	NSRect windowFrame = [_popoverWindow frameRectForContentRect:contentRect];
	CGFloat arrowInset = INPOPOVER_ARROW_HEIGHT + INPOPOVER_CORNER_RADIUS + INPOPOVER_ARROW_WIDTH/2.0;	// inset from windowFrame
	switch (direction) {
		case INPopoverArrowDirectionUp:
		{ 
			CGFloat xOrigin = rint(NSMidX(_screenRect) - (windowFrame.size.width - arrowInset*2.0) * arrowPosition - arrowInset);
			CGFloat yOrigin = NSMinY(_screenRect) - windowFrame.size.height;
			windowFrame.origin = NSMakePoint(xOrigin, yOrigin);
			break;
		}
		case INPopoverArrowDirectionDown:
		{
			CGFloat xOrigin = rint(NSMidX(_screenRect) - (windowFrame.size.width - arrowInset*2.0) * arrowPosition - arrowInset);
			windowFrame.origin = NSMakePoint(xOrigin, NSMaxY(_screenRect));
			break;
		}
		case INPopoverArrowDirectionLeft:
		{
			CGFloat yOrigin = rint(NSMidY(_screenRect) - (windowFrame.size.height - arrowInset*2.0) * arrowPosition - arrowInset);
			windowFrame.origin = NSMakePoint(NSMaxX(_screenRect), yOrigin);
			break;
		}
		case INPopoverArrowDirectionRight:
		{
			CGFloat xOrigin = NSMinX(_screenRect) - windowFrame.size.width;
			CGFloat yOrigin = rint(NSMidY(_screenRect) - (windowFrame.size.height - arrowInset*2.0) * arrowPosition - arrowInset);
			windowFrame.origin = NSMakePoint(xOrigin, yOrigin);
			break;
		}
		default:
			// If no arrow direction is specified, just return an empty rect
			windowFrame = NSZeroRect;
	}
	return windowFrame;
}

#pragma mark -
#pragma mark Memory Management

- (void)dealloc
{
	[_contentViewController release];
	[_popoverWindow release];
	[super dealloc];
}

- (void) animationDidStop:(CAAnimation *)animation finished:(BOOL)flag 
{
#pragma unused(animation)
#pragma unused(flag)
	// Detect the end of fade out and close the window
	if(0.0 == [_popoverWindow alphaValue])
		[self _closePopoverAndResetVariables];
	else if(1.0 == [_popoverWindow alphaValue]) {
		[[_positionView window] addChildWindow:_popoverWindow ordered:NSWindowAbove];
		[self _callDelegateMethod:@selector(popoverDidShow:)];
	}
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
	// when the user clicks in the parent window for activating the app, the parent window becomes key which prevents 
	if ([_popoverWindow isVisible])
		[self performSelector:@selector(checkPopoverKeyWindowStatus) withObject:nil afterDelay:0];
}

- (void)checkPopoverKeyWindowStatus
{
	id parentWindow = [_positionView window]; // could be INPopoverParentWindow
	BOOL isKey = [parentWindow respondsToSelector:@selector(isReallyKeyWindow)] ? [parentWindow isReallyKeyWindow] : [parentWindow isKeyWindow];
	if (isKey)
		[_popoverWindow makeKeyWindow];
}

#pragma mark -
#pragma mark Getters

- (NSView*)positionView { return _positionView; }

- (NSColor*)color { return _popoverWindow.frameView.color; }

- (CGFloat)borderWidth { return _popoverWindow.frameView.borderWidth; }

- (NSColor*)borderColor { return _popoverWindow.frameView.borderColor; }

- (NSColor*)topHighlightColor { return _popoverWindow.frameView.topHighlightColor; }

- (INPopoverArrowDirection)arrowDirection { return _popoverWindow.frameView.arrowDirection; }

- (CGFloat)arrowPosition { return _popoverWindow.frameView.arrowPosition; }

- (NSView*)contentView { return [self.popoverWindow contentView]; }

- (NSSize)contentSize { return _contentSize; }

- (NSWindow*)popoverWindow { return _popoverWindow; }

- (NSViewController*)contentViewController { return _contentViewController; }

- (BOOL)popoverIsVisible { return [_popoverWindow isVisible]; }

#pragma mark -
#pragma mark Setters

- (void)setColor:(NSColor *)newColor { _popoverWindow.frameView.color = newColor; }

- (void)setBorderWidth:(CGFloat)newBorderWidth { _popoverWindow.frameView.borderWidth = newBorderWidth; }

- (void)setBorderColor:(NSColor *)newBorderColor { _popoverWindow.frameView.borderColor = newBorderColor; }

- (void)setTopHighlightColor:(NSColor *)newTopHighlightColor { _popoverWindow.frameView.topHighlightColor = newTopHighlightColor; }

- (void)setContentViewController:(NSViewController *)newContentViewController
{
	if (_contentViewController != newContentViewController) {
		[_popoverWindow setContentView:nil]; // Clear the content view
		[_contentViewController release];
		_contentViewController = [newContentViewController retain];
		NSView *contentView = [_contentViewController view];
		self.contentSize = [contentView frame].size;
		[_popoverWindow setContentView:contentView];
	}
}

- (void)setContentSize:(NSSize)newContentSize
{
	// We use -frameRectForContentRect: just to get the frame size because the origin it returns is not the one we want to use. Instead, -windowFrameWithSize:andArrowDirection: is used to  complete the frame
	_contentSize = newContentSize;
	NSRect adjustedRect = [self popoverFrameWithSize:newContentSize andArrowDirection:self.arrowDirection andArrowPosition:self.arrowPosition];
	[_popoverWindow setFrame:adjustedRect display:YES animate:self.animates];
}
	
#pragma mark -

- (void)_setPositionView:(NSView*)newPositionView
{
	if (_positionView != newPositionView) {
		[_positionView release];
		_positionView = [newPositionView retain];
	}
}

- (void)_setArrowDirection:(INPopoverArrowDirection)direction { 
	_popoverWindow.frameView.arrowDirection = direction; 
}

- (void)_setArrowPosition:(CGFloat)position {
	_popoverWindow.frameView.arrowPosition = position;
}

#pragma mark -
#pragma mark Private

// Set the default values for all the properties as described in the header documentation
- (void)_setInitialPropertyValues
{
	// Create an empty popover window
	_popoverWindow = [[INPopoverWindow alloc] initWithContentRect:NSZeroRect styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
	
	// set defaults like iCal popover
	self.color = [NSColor colorWithCalibratedWhite:0.94 alpha:0.92];
	self.borderColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.92];
	self.borderWidth = 1.0;
	self.closesWhenPopoverResignsKey = YES;
	self.closesWhenApplicationBecomesInactive = NO;
	self.animates = YES;
	
	// create animation to get callback - delegate is set when opening popover to avoid memory cycles
	CAAnimation *animation = [CABasicAnimation animation];
	[_popoverWindow setAnimations:[NSDictionary dictionaryWithObject:animation forKey:@"alphaValue"]];
}

- (NSScreen*)_positionViewScreen
{
	// find screen that contains the center point of the position view
	NSPoint positionPoint = NSMakePoint(NSMidX(_screenRect), NSMidY(_screenRect));
	for (NSScreen *screen in [NSScreen screens]) {
		if (NSPointInRect(positionPoint, [screen visibleFrame]))
			return screen;
	}
	return [[_positionView window] screen];
}

- (BOOL)_arrowDirection:(INPopoverArrowDirection)direction fitsScreenWithArrowPosition:(CGFloat *)outArrowPosition
{
	CGFloat arrowPosition = INPOPOVER_ARROW_DEFAULT_POSITION;
	NSRect screenFrame = [[self _positionViewScreen] visibleFrame];
	// If it already falls within the screen bounds with default arrow position then no need to go any further
	NSSize contentSize = self.contentSize;
	NSRect windowFrame = [self popoverFrameWithSize:contentSize andArrowDirection:direction andArrowPosition:arrowPosition];
	if (NSContainsRect(screenFrame, windowFrame)) {
		if (outArrowPosition)
			*outArrowPosition = arrowPosition;
		return YES;
	}
	// Calculate the remaining space on each side
	CGFloat left = NSMinX(_screenRect) - NSMinX(screenFrame);
	CGFloat right = NSMaxX(screenFrame) - NSMaxX(_screenRect);
	CGFloat up = NSMaxY(screenFrame) - NSMaxY(_screenRect);
	CGFloat down = NSMinY(_screenRect) - NSMinY(screenFrame);
	CGFloat arrowInset = INPOPOVER_ARROW_HEIGHT + INPOPOVER_CORNER_RADIUS + INPOPOVER_ARROW_WIDTH/2.0;	// inset from windowFrame
	// Try to reposition arrow
	if (   (direction == INPopoverArrowDirectionUp && down >= windowFrame.size.height)
		|| (direction == INPopoverArrowDirectionDown && up >= windowFrame.size.height))
	{
		CGFloat leftSpace = NSMidX(_screenRect) - NSMinX(screenFrame);
		CGFloat rightSpace = NSMaxX(screenFrame) - NSMidX(_screenRect);
		CGFloat minSpace = windowFrame.size.width/2.0;
		
		if (leftSpace < minSpace && leftSpace > arrowInset) {
			arrowPosition -= (minSpace - leftSpace) / (windowFrame.size.width - arrowInset*2.0);
		} else if (rightSpace < minSpace && rightSpace > arrowInset) {
			arrowPosition += (minSpace - rightSpace) / (windowFrame.size.width - arrowInset*2.0);
		}
	}
	else if (   (direction == INPopoverArrowDirectionLeft && right >= windowFrame.size.width)
			 || (direction == INPopoverArrowDirectionRight && left >= windowFrame.size.width))
	{
		CGFloat upSpace = NSMaxY(screenFrame) - NSMidY(_screenRect);
		CGFloat downSpace = NSMidY(_screenRect) - NSMinY(screenFrame);
		CGFloat minSpace = windowFrame.size.height/2.0;
		
		if (upSpace < minSpace && upSpace > arrowInset) {
			arrowPosition += (minSpace - upSpace) / (windowFrame.size.height - arrowInset*2.0);
		} else if (downSpace < minSpace && downSpace > arrowInset) {
			arrowPosition -= (minSpace - downSpace) / (windowFrame.size.height - arrowInset*2.0);
		}
	}
	windowFrame = [self popoverFrameWithSize:contentSize andArrowDirection:direction andArrowPosition:arrowPosition];
	if (NSContainsRect(screenFrame, windowFrame)) {
		if (outArrowPosition)
			*outArrowPosition = arrowPosition;
		return YES;
	}
	return NO;
}

// Figure out which direction best stays in screen bounds
- (INPopoverArrowDirection)_arrowDirectionWithPreferredArrowDirection:(INPopoverArrowDirection)direction arrowPosition:(CGFloat *)outArrowPosition
{
	// If the window with the preferred arrow direction already falls within the screen bounds then no need to go any further
	if ([self _arrowDirection:direction fitsScreenWithArrowPosition:outArrowPosition])
		return direction;
	
	// Next thing to try is making the popover go opposite of its current direction
	INPopoverArrowDirection newDirection = INPopoverArrowDirectionUndefined;
	switch (direction) {
		case INPopoverArrowDirectionUp:
			newDirection = INPopoverArrowDirectionDown;
			break;
		case INPopoverArrowDirectionDown:
			newDirection = INPopoverArrowDirectionUp;
			break;
		case INPopoverArrowDirectionLeft:
			newDirection = INPopoverArrowDirectionRight;
			break;
		case INPopoverArrowDirectionRight:
			newDirection = INPopoverArrowDirectionLeft;
			break;
		default:
			break;
	}
	// If the popover now fits within bounds, then return the newly adjusted direction
	if ([self _arrowDirection:newDirection fitsScreenWithArrowPosition:outArrowPosition])
		return newDirection;
	
	// Now the next thing to try is the direction with the most space
	NSRect screenFrame = [[self _positionViewScreen] visibleFrame];
	switch (direction) {
		case INPopoverArrowDirectionUp:
		case INPopoverArrowDirectionDown:
		{
			CGFloat left = NSMinX(_screenRect);
			CGFloat right = screenFrame.size.width - NSMaxX(_screenRect);
			newDirection = (right > left) ? INPopoverArrowDirectionLeft : INPopoverArrowDirectionRight;
			break;
		}
		case INPopoverArrowDirectionLeft:
		case INPopoverArrowDirectionRight:
		{
			CGFloat up = screenFrame.size.height - NSMaxY(_screenRect);
			CGFloat down = NSMinY(_screenRect);
			newDirection = (down > up) ? INPopoverArrowDirectionUp : INPopoverArrowDirectionDown;
			break;
		}
		default:
			break;
	}
	// If the popover now fits within bounds, then return the newly adjusted direction
	if ([self _arrowDirection:newDirection fitsScreenWithArrowPosition:outArrowPosition])
		return newDirection;
	
	// If that didn't fit, then that means that it will be out of bounds on every side so just return the original direction
	return direction;
}

- (void)_positionViewFrameChanged:(NSNotification*)notification
{
	NSRect superviewBounds = [[self.positionView superview] bounds];
	if (!(NSContainsRect(superviewBounds, [self.positionView frame]))) {
		[self forceClosePopover:nil]; // If the position view goes off screen then close the popover
		return;
	}
	NSRect newFrame = [_popoverWindow frame];
	_screenRect = [self.positionView convertRect:_viewRect toView:nil]; // Convert the rect to window coordinates
	_screenRect.origin = [[self.positionView window] convertBaseToScreen:_screenRect.origin]; // Convert window coordinates to screen coordinates
	NSRect calculatedFrame = [self popoverFrameWithSize:self.contentSize andArrowDirection:self.arrowDirection andArrowPosition:self.arrowPosition]; // Calculate the window frame based on the arrow direction
	newFrame.origin = calculatedFrame.origin;
	[_popoverWindow setFrame:newFrame display:YES animate:NO]; // Set the frame of the window
}

- (void)_closePopoverAndResetVariables
{
	[[self retain] autorelease]; // make sure we don't get released during the following, e.g. by the delegate method
	NSWindow *positionWindow = [self.positionView window];
	[_popoverWindow orderOut:nil]; // Close the window 
	[self _callDelegateMethod:@selector(popoverDidClose:)]; // Call the delegate to inform that the popover has closed
	[positionWindow removeChildWindow:_popoverWindow]; // Remove it as a child window
	[positionWindow makeKeyAndOrderFront:nil];
	// Clear all the ivars
	[self _setArrowDirection:INPopoverArrowDirectionUndefined];
	[self _setArrowPosition:INPOPOVER_ARROW_DEFAULT_POSITION];
	[self _setPositionView:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[[_popoverWindow animationForKey:@"alphaValue"] setDelegate:nil];	// reset delegate so it doesn't retain us
	_screenRect = NSZeroRect;
	_viewRect = NSZeroRect;
}

- (void)_callDelegateMethod:(SEL)selector
{
	if ([self.delegate respondsToSelector:selector]) {
		[self.delegate performSelector:selector withObject:self];
	}
}

@end

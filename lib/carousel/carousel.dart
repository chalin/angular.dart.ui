// Copyright (C) 2013 - 2014 Angular Dart UI authors. Please see AUTHORS.md.
// https://github.com/akserg/angular.dart.ui
// All rights reserved.  Please see the LICENSE.md file.
library angular.ui.carousel;

import 'dart:html' as dom;

import 'dart:async' as async;
import 'package:angular/angular.dart';

import 'package:angular_ui/utils/transition.dart';
import 'package:angular_ui/utils/timeout.dart';

import 'package:logging/logging.dart' show Logger;
final _log = new Logger('angular.ui.carousel');

/**
 * Carousel Module.
 */
class CarouselModule extends Module {
  CarouselModule() {
    install(new TransitionModule());
    type(Carousel);
    type(Slide);
  }
}


/**
 * Carousel component.
 */
@NgComponent(
    selector: 'carousel',
    publishAs: 'c',
    applyAuthorStyles: true,
    visibility: NgDirective.CHILDREN_VISIBILITY,
//    cssUrls: const ["packages/angular_ui/css/carousel.css"],
    templateUrl: 'packages/angular_ui/carousel/carousel.html')
class Carousel implements NgDetachAware {

  @NgOneWay('no-transition') bool noTransition = false;
  int _interval = 0;
  @NgOneWay('interval') set interval(int interval) {
    _interval = interval;
    restartTimer();
  }
  @NgOneWay('no-pause') bool noPause = false;
  List<Slide> slides = [];
  int _currentIndex = -1;
  async.Completer _currentTimeout;
  bool _isPlaying = false;
  Slide _currentSlide;

  bool _destroyed = false;

  Transition _transition;
  async.Completer _currentTransition;
  Timeout _timeout;

  Carousel(this._transition, this._timeout) {
    _log.fine('CarouselComponent');
  }

  void next() {
    var newIndex = (_currentIndex + 1) % slides.length;
    //Prevent this user-triggered transition from occurring if there is already one in progress
    if (_currentTransition == null) {
      select(slides[newIndex], direction:'next');
    }
  }

  void prev() {
    var newIndex = _currentIndex - 1 < 0 ? slides.length - 1 : _currentIndex - 1;

    //Prevent this user-triggered transition from occurring if there is already one in progress
    if (_currentTransition == null) {
      select(slides[newIndex], direction:'prev');
    }
  }

  bool isActive(Slide slide) {
    return _currentSlide == slide;
  }

  void play() {
    if (!_isPlaying) {
      _isPlaying = true;
      restartTimer();
    }
  }

  void pause() {
    if (!noPause) {
      _isPlaying = false;
      resetTimer();
    }
  }

  void select(Slide nextSlide, {String direction: null}) {
    if (slides.length > 0) {
      int nextIndex = slides.indexOf(nextSlide);
      // Decide direction if it's not given
      if (direction == null) {
        direction = nextIndex > _currentIndex ? 'next' : 'prev';
      }
      if (nextSlide != null && nextSlide != _currentSlide) {
        if (_currentTransition != null && !_currentTransition.isCompleted) {
          _currentTransition.completeError('Transition cancelled');
          //Timeout so ng-class in template has time to fix classes for finished slide
          _timeout(() => _goNext(direction, nextIndex));
        } else {
          _goNext(direction, nextIndex);
        }
      }
    }
  }

  void _goNext(String direction, int nextIndex) {
    Slide nextSlide = slides[nextIndex];
    //_log.finer('goNext($direction, $nextIndex)');
    // Scope has been destroyed, stop here.
    if (_destroyed) {
      return;
    }
    // If we have a slide to transition from and we have a transition type and we're allowed, go
    if (_currentSlide != null && direction != null && direction.isNotEmpty && !noTransition && nextSlide.element != null) {
      // We shouldn't do class manip in here, but it's the same weird thing bootstrap does. need to fix sometime
      //nextSlide.element.classes.add(direction);
      nextSlide.element.classes.add(direction);

      var reflow = nextSlide.element.children[0].offsetWidth; //force reflow

      //Set all other slides to stop doing their stuff for the new transition
      slides.forEach((Slide slide) {
//        extend({'direction': slide.direction, 'entering': slide.entering, 'leaving': slide.leaving, 'active': slide.active },
//            [{'direction': '', 'entering': false, 'leaving': false, 'active': false}]);
        slide.direction = '';
        slide.entering = false;
        slide.leaving = false;
        slide.active = false;
        slide.next = false;
      });

      nextSlide.direction = direction;
      nextSlide.entering = true;
      nextSlide._active = true;
      nextSlide.next = true;

      if (_currentSlide != null) {
        _currentSlide.direction = direction;
        _currentSlide.leaving = true;
      }

      _currentTransition = _transition(nextSlide.element, {});

      // We have to create new pointers inside a closure since next & current will change
      var closure = (next, current) {
        _currentTransition.future.then((onValue) {
          _transitionDone(next, current);
        }, onError:(e) {
          _transitionDone(next, current);
        });
      };
      //
      closure(nextSlide, _currentSlide);
    } else {
      _transitionDone(nextSlide, _currentSlide);
    }
    _currentSlide = nextSlide;
    _currentIndex = nextIndex;
    //every time you change slides, reset the timer
    restartTimer();
  }

  void _transitionDone(Slide next, Slide current) {
    next.direction = '';
    next.entering = false;
    next.leaving = false;
    next._active = true;
    //
    if (current != null) {
      current.direction = '';
      current.entering = false;
      current.leaving = false;
      current.active = false;
    }
    _currentTransition = null;
  }


  /* Allow outside people to call indexOf on slides array */
  int indexOfSlide (slide) {
    return slides.indexOf(slide);
  }

  void restartTimer() {
    resetTimer();
    if (_interval != null && _interval >= 0) {
      //_log.fine('restartTimer - interval: ${_interval}');
      _currentTimeout = _timeout(timerFn, delay: _interval);
    }
  }

  void resetTimer() {
    if (_currentTimeout != null) {
      _timeout.cancel(_currentTimeout);
      _currentTimeout = null;
    }
  }

  void timerFn() {
    // this is called from timeout. restart async so the previous can properly
    // switch to completed before restarting

    //_log.fine('timerFn');
    new async.Future(() {
      if (_isPlaying) {
        next();
        restartTimer();
      } else {
        pause();
      }
    });
  }

  void addSlide(Slide slide, dom.Element element) {
    slide.element = element;
    slides.add(slide);
    //if this is the first slide or the slide is set to active, select it
    if(slides.length == 1 || slide.active) {
      select(slides[slides.length - 1]);
      if (slides.length == 1) {
        play();
      }
    } else {
      slide.active = false;
    }
  }

  void removeSlide(Slide slide) {
    //get the index of the slide inside the carousel
    var index = slides.indexOf(slide);
    slides.removeAt(index);
    if (slides.length > 0 && slide.active) {
      if (index >= slides.length) {
        select(slides[index - 1]);
      } else {
        select(slides[index]);
      }
    } else if (_currentIndex > index) {
      _currentIndex--;
    }
  }

  void detach() {
    _destroyed = true;
    resetTimer();
  }
}


@NgComponent(
    selector: 'slide',
    publishAs: 's',
    applyAuthorStyles: true,
    templateUrl: 'packages/angular_ui/slide/slide.html')
class Slide implements NgShadowRootAware, NgDetachAware {
  bool _active = false;
  @NgTwoWay('active')
  set active(bool value) {
    if(value == null) {
      return;
    }
    if(value != _active) {
      _active = value;
      if(_active) {
        _carouselCtrl.select(this);
      }
    }
  }
  bool get active => _active;

  String _direction = '';

  @NgTwoWay('direction') String get direction => _direction;
  set direction(String val) {
    _direction = val;
  }

  @NgTwoWay('entering') bool entering = false;
  @NgTwoWay('leaving') bool leaving = false;
  @NgTwoWay('next') bool next = false;

  //Scope  scope;
  dom.Element element;
  Carousel _carouselCtrl;

  Slide(this.element, this._carouselCtrl) {
    _log.fine('SlideComponent');
  }

  @override
  void detach() {
    //when the scope is destroyed then remove the slide from the current slides array
    _carouselCtrl.removeSlide(this);
  }


  @override
  void onShadowRoot(dom.ShadowRoot shadowRoot) {
    _carouselCtrl.addSlide(this, shadowRoot.querySelector('div'));
  }
}
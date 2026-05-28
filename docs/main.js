gsap.registerPlugin(ScrollTrigger);

const motion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

if (!motion) {
  gsap.defaults({ ease: "power3.out", duration: 0.85 });

  gsap.from(".topbar", { y: -28, autoAlpha: 0 });
  gsap.from(".hero-copy > *", { y: 34, autoAlpha: 0, stagger: 0.09, delay: 0.12 });
  gsap.from(".product-shell", { y: 42, rotationX: 8, autoAlpha: 0, transformOrigin: "50% 100%", delay: 0.22 });
  gsap.from(".bubble, .composer", { x: 24, autoAlpha: 0, stagger: 0.12, delay: 0.75 });

  gsap.to(".product-shell", {
    y: -24,
    scrollTrigger: {
      trigger: ".hero",
      start: "top top",
      end: "bottom top",
      scrub: 0.8
    }
  });

  ScrollTrigger.batch(".feature-card, .steps li", {
    start: "top 82%",
    once: true,
    onEnter: (items) => gsap.from(items, { y: 30, autoAlpha: 0, stagger: 0.08, overwrite: true })
  });

  gsap.from(".metabolism .section-heading > *", {
    y: 34,
    autoAlpha: 0,
    stagger: 0.12,
    scrollTrigger: {
      trigger: ".metabolism",
      start: "top 72%",
      once: true
    }
  });

  gsap.from(".metabolism-card", {
    y: 46,
    scale: 0.96,
    autoAlpha: 0,
    stagger: 0.09,
    scrollTrigger: {
      trigger: ".metabolism-flow",
      start: "top 78%",
      once: true
    }
  });

  gsap.to(".metabolism-card span", {
    y: -8,
    repeat: -1,
    yoyo: true,
    duration: 1.6,
    ease: "sine.inOut",
    stagger: {
      each: 0.12,
      repeat: -1,
      yoyo: true
    }
  });

  ScrollTrigger.batch(".install-steps li", {
    start: "top 84%",
    once: true,
    onEnter: (items) => gsap.from(items, { y: 34, autoAlpha: 0, stagger: 0.08, overwrite: true })
  });
}
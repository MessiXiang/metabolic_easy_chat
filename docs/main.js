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
}
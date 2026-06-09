{ctx}: {
  desktop = ctx.self.nixosConfigurations.desktop-ci.config.system.build.toplevel;
  usb = ctx.self.nixosConfigurations.usb.config.system.build.toplevel;
  laptop = ctx.self.nixosConfigurations.laptop.config.system.build.toplevel;
}

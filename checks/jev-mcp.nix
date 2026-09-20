{ctx}: {
  jev-mcp = ctx.pkgs.closureInfo {
    rootPaths = [ctx.desktopJevMcpWrapper];
  };
}

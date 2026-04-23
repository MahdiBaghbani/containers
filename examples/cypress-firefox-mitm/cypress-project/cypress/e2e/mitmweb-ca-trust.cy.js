describe("mitmweb CA trust", () => {
  it("loads mitmweb over https", () => {
    cy.visit("https://mitmproxy.docker/");
    cy.contains("mitm").should("exist");
  });
});

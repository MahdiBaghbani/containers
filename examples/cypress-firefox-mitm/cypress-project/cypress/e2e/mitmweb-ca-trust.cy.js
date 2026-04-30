describe("mitmweb CA trust", () => {
  it("loads mitmweb over https", () => {
    cy.visit("https://cypress-mitmproxy.docker/");
    cy.contains("mitm").should("exist");
  });
});

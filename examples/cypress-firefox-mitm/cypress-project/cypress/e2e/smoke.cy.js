describe("smoke", () => {
  it("loads a simple page", () => {
    cy.visit("data:text/html,<h1>ok</h1>");
    cy.contains("ok");
  });
});

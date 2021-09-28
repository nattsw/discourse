import DiscourseRoute from "discourse/routes/discourse";

export default DiscourseRoute.extend({
  model() {
    return this.store.findAll("pending-post");
  },

  activate() {
    this.messageBus.subscribe("/user", (data) => {
      if (data.hasOwnProperty("pending_posts_count")) { this.refresh(); }
    });
  },

  deactivate() {
    this.messageBus.unsubscribe("/user");
  }
});

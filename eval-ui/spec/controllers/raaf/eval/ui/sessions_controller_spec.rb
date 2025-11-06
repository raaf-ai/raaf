# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Eval::UI::SessionsController, type: :controller do
  routes { RAAF::Eval::UI::Engine.routes }

  let(:valid_attributes) do
    {
      name: "Test Session",
      description: "A test evaluation session",
      session_type: "draft"
    }
  end

  let(:invalid_attributes) do
    {
      name: "",
      session_type: "invalid"
    }
  end

  describe "GET #index" do
    let!(:session1) { create(:session, name: "Session 1") }
    let!(:session2) { create(:session, name: "Session 2") }

    it "returns a success response" do
      get :index
      expect(response).to be_successful
    end

    it "assigns @sessions" do
      get :index
      expect(assigns(:sessions)).to match_array([session1, session2])
    end

    context "with filter parameter" do
      let!(:saved_session) { create(:session, session_type: "saved") }
      let!(:draft_session) { create(:session, session_type: "draft") }

      it "filters by session type" do
        get :index, params: { filter: "saved" }
        expect(assigns(:sessions)).to contain_exactly(saved_session)
      end
    end
  end

  describe "GET #show" do
    let(:session) { create(:session) }

    it "returns a success response" do
      get :show, params: { id: session.id }
      expect(response).to be_successful
    end

    it "assigns @session" do
      get :show, params: { id: session.id }
      expect(assigns(:session)).to eq(session)
    end
  end

  describe "POST #create" do
    context "with valid params" do
      it "creates a new Session" do
        expect {
          post :create, params: { session: valid_attributes }
        }.to change(RAAF::Eval::UI::Session, :count).by(1)
      end

      it "redirects to the created session" do
        post :create, params: { session: valid_attributes }
        expect(response).to redirect_to(session_path(RAAF::Eval::UI::Session.last))
      end
    end

    context "with invalid params" do
      it "does not create a new Session" do
        expect {
          post :create, params: { session: invalid_attributes }
        }.not_to change(RAAF::Eval::UI::Session, :count)
      end

      it "returns unprocessable entity status" do
        post :create, params: { session: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PUT #update" do
    let(:session) { create(:session) }
    let(:new_attributes) { { name: "Updated Name", description: "Updated description" } }

    context "with valid params" do
      it "updates the requested session" do
        put :update, params: { id: session.id, session: new_attributes }
        session.reload
        expect(session.name).to eq("Updated Name")
        expect(session.description).to eq("Updated description")
      end

      it "redirects to the session" do
        put :update, params: { id: session.id, session: new_attributes }
        expect(response).to redirect_to(session_path(session))
      end
    end

    context "with invalid params" do
      it "returns unprocessable entity status" do
        put :update, params: { id: session.id, session: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE #destroy" do
    let!(:session) { create(:session) }

    it "destroys the requested session" do
      expect {
        delete :destroy, params: { id: session.id }
      }.to change(RAAF::Eval::UI::Session, :count).by(-1)
    end

    it "redirects to the sessions list" do
      delete :destroy, params: { id: session.id }
      expect(response).to redirect_to(sessions_path)
    end
  end
end

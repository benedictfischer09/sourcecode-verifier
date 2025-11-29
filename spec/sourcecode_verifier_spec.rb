RSpec.describe SourcecodeVerifier do
  it "has a version number" do
    expect(SourcecodeVerifier::VERSION).not_to be nil
  end

  describe ".verify" do
    it "raises an error without gem name and version" do
      expect {
        SourcecodeVerifier.verify(nil, nil)
      }.to raise_error(SourcecodeVerifier::Error, /Gem name and version are required/)
    end
  end

  describe ".verify_local" do
    it "raises an error without required paths" do
      expect {
        SourcecodeVerifier.verify_local(nil, nil)
      }.to raise_error(SourcecodeVerifier::Error, /Both gem_path and source_path are required/)
    end
    
    it "raises an error if paths don't exist" do
      expect {
        SourcecodeVerifier.verify_local('/nonexistent/path', '/another/nonexistent/path')
      }.to raise_error(SourcecodeVerifier::Error, /does not exist/)
    end
  end
end